//! ctypes._aix - AIX-specific library finding
//! Reference: cpython/Lib/ctypes/_aix.py
//!
//! CPython exports: find_library, AIX_ABI
//!
//! Provides AIX-specific implementation of find_library().
//! AIX supports two styles of shared libraries:
//! - SVR4 style: regular files (libFOO.so)
//! - AIX style: archive members (libFOO.a(shr.o))

const std = @import("std");
const builtin = @import("builtin");

// ============================================================================
// AIX ABI Detection
// ============================================================================

/// Executable bit size - 32 or 64
/// Used to filter archive member search by size (-X32 or -X64)
pub const AIX_ABI: u8 = @sizeOf(*anyopaque) * 8;

// ============================================================================
// Library Search Paths
// ============================================================================

/// Get library search paths from environment and executable
pub fn getLibpaths(allocator: std.mem.Allocator) !std.ArrayList([]const u8) {
    var paths = std.ArrayList([]const u8).init(allocator);

    // Check LD_LIBRARY_PATH first (preferred)
    if (std.posix.getenv("LD_LIBRARY_PATH")) |ld_path| {
        var iter = std.mem.splitScalar(u8, ld_path, ':');
        while (iter.next()) |path| {
            try paths.append(path);
        }
    } else if (std.posix.getenv("LIBPATH")) |lib_path| {
        // Fall back to LIBPATH
        var iter = std.mem.splitScalar(u8, lib_path, ':');
        while (iter.next()) |path| {
            try paths.append(path);
        }
    }

    // Add standard paths
    try paths.append("/usr/lib");
    try paths.append("/lib");

    return paths;
}

// ============================================================================
// Archive Member Parsing
// ============================================================================

/// Information about a shared library member in an archive
pub const MemberInfo = struct {
    base: []const u8,
    member: []const u8,
};

/// Legacy AIX member names
const legacy_32bit = [_][]const u8{ "shr.o", "shr4.o" };
const legacy_64bit = [_][]const u8{ "shr_64.o", "shr64.o", "shr4_64.o" };

/// Get legacy member name based on ABI
fn getLegacyMember() ?[]const u8 {
    if (AIX_ABI == 64) {
        // Try 64-bit legacy names
        for (legacy_64bit) |name| {
            return name;
        }
    } else {
        // Try 32-bit legacy names
        for (legacy_32bit) |name| {
            return name;
        }
    }
    return null;
}

/// Find a shared library member in an archive
fn getMember(name: []const u8, members: []const []const u8) ?[]const u8 {
    // First, try exact match: libFOO.so
    for (members) |member| {
        if (std.mem.indexOf(u8, member, name)) |_| {
            if (std.mem.endsWith(u8, member, ".so")) {
                return member;
            }
        }
    }

    // Try with 64 suffix for 64-bit
    if (AIX_ABI == 64) {
        for (members) |member| {
            if (std.mem.indexOf(u8, member, name)) |_| {
                if (std.mem.indexOf(u8, member, "64")) |_| {
                    return member;
                }
            }
        }
    }

    // Fall back to legacy naming
    return getLegacyMember();
}

// ============================================================================
// find_library Implementation
// ============================================================================

/// CPython: def find_library(name)
/// AIX implementation of ctypes.util.find_library()
///
/// Find an archive member that will dlopen(). If not available,
/// also search for a file (or link) with a .so suffix.
///
/// AIX supports two types of schemes:
/// - SVR4 format: commonly suffixed with .so
/// - AIX scheme: library (archive) ending with .a
///
/// As an archive has multiple members (32-bit and 64-bit) in one file,
/// the argument passed to dlopen must include both the library and
/// member names: "libFOO.a(shr.o)"
pub fn find_library(allocator: std.mem.Allocator, name: []const u8) ?[]const u8 {
    const libpaths = getLibpaths(allocator) catch return null;
    defer libpaths.deinit();

    // Try to find archive with member
    if (findShared(allocator, libpaths.items, name)) |info| {
        // Return in format: base(member)
        const result = std.fmt.allocPrint(allocator, "{s}({s})", .{ info.base, info.member }) catch return null;
        return result;
    }

    // Try to find .so file directly
    const soname = std.fmt.allocPrint(allocator, "lib{s}.so", .{name}) catch return null;
    defer allocator.free(soname);

    for (libpaths.items) |dir| {
        // Skip /lib (symlink to /usr/lib on AIX)
        if (std.mem.eql(u8, dir, "/lib")) continue;

        const full_path = std.fmt.allocPrint(allocator, "{s}/{s}", .{ dir, soname }) catch continue;

        const file = std.fs.openFileAbsolute(full_path, .{}) catch {
            allocator.free(full_path);
            continue;
        };
        file.close();

        // Found it - return just the soname (not full path)
        allocator.free(full_path);
        return allocator.dupe(u8, soname) catch null;
    }

    return null;
}

/// Find a shared library in an archive
fn findShared(allocator: std.mem.Allocator, paths: []const []const u8, name: []const u8) ?MemberInfo {
    for (paths) |dir| {
        // Skip /lib (symlink to /usr/lib)
        if (std.mem.eql(u8, dir, "/lib")) continue;

        // Build archive path: lib<name>.a
        const base = std.fmt.allocPrint(allocator, "lib{s}.a", .{name}) catch continue;
        defer allocator.free(base);

        const archive = std.fmt.allocPrint(allocator, "{s}/{s}", .{ dir, base }) catch continue;
        defer allocator.free(archive);

        // Check if archive exists
        const file = std.fs.openFileAbsolute(archive, .{}) catch continue;
        file.close();

        // Archive exists, try to find member
        // In a full implementation, we would parse the archive to get members
        // For now, use legacy naming
        if (getLegacyMember()) |member| {
            return .{
                .base = allocator.dupe(u8, base) catch return null,
                .member = member,
            };
        }
    }

    return null;
}

// ============================================================================
// Archive Header Parsing (Stub)
// ============================================================================

/// CPython: def get_ld_headers(file)
/// Parse the header of the loader section of executable and archives.
/// Would call /usr/bin/dump -H as a subprocess.
pub fn getLdHeaders(allocator: std.mem.Allocator, file: []const u8) ?[]const []const u8 {
    _ = allocator;
    _ = file;
    // Would execute: /usr/bin/dump -X{AIX_ABI} -H {file}
    // For AOT compilation, we skip subprocess execution
    return null;
}

/// CPython: def get_shared(ld_headers)
/// Extract shareable objects from ld_headers.
pub fn getShared(ld_headers: []const []const u8) []const []const u8 {
    _ = ld_headers;
    // Would parse dump output for member names
    return &[_][]const u8{};
}

// ============================================================================
// Version Comparison
// ============================================================================

/// CPython: def _last_version(libnames, sep)
/// Sort list of library names and return highest numbered version.
pub fn lastVersion(libnames: []const []const u8, sep: u8) ?[]const u8 {
    if (libnames.len == 0) return null;

    var best: ?[]const u8 = null;
    var best_version: ?[]const u32 = null;

    for (libnames) |libname| {
        const version = parseVersion(libname, sep);
        if (best_version == null or compareVersions(version, best_version.?) > 0) {
            best = libname;
            best_version = version;
        }
    }

    return best;
}

/// Parse version numbers from a library name
fn parseVersion(libname: []const u8, sep: u8) []const u32 {
    _ = libname;
    _ = sep;
    // Would parse "libfoo.so.1.2.3" -> [1, 2, 3]
    return &[_]u32{};
}

/// Compare two version arrays
fn compareVersions(a: []const u32, b: []const u32) i32 {
    const min_len = @min(a.len, b.len);
    for (a[0..min_len], b[0..min_len]) |av, bv| {
        if (av < bv) return -1;
        if (av > bv) return 1;
    }
    if (a.len < b.len) return -1;
    if (a.len > b.len) return 1;
    return 0;
}

// ============================================================================
// Tests
// ============================================================================

test "AIX_ABI" {
    // Should be 32 or 64
    try std.testing.expect(AIX_ABI == 32 or AIX_ABI == 64);
}

test "getLegacyMember" {
    const member = getLegacyMember();
    try std.testing.expect(member != null);
}

test "compareVersions" {
    const v1 = [_]u32{ 1, 2, 3 };
    const v2 = [_]u32{ 1, 2, 4 };
    const v3 = [_]u32{ 1, 2, 3 };

    try std.testing.expect(compareVersions(&v1, &v2) < 0);
    try std.testing.expect(compareVersions(&v2, &v1) > 0);
    try std.testing.expect(compareVersions(&v1, &v3) == 0);
}
