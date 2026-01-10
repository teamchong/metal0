//! test.test_ctypes.test_macholib - Tests for Mach-O library handling
//! Reference: cpython/Lib/test/test_ctypes/test_macholib.py
//!
//! Tests for macOS-specific Mach-O library loading and analysis.

const std = @import("std");
const builtin = @import("builtin");
const _support = @import("_support.zig");

// ============================================================================
// Mach-O Constants
// ============================================================================

pub const MH_MAGIC_64 = 0xfeedfacf;
pub const MH_CIGAM_64 = 0xcffaedfe;
pub const MH_MAGIC = 0xfeedface;
pub const MH_CIGAM = 0xcefaedfe;

pub const MH_EXECUTE = 0x2;
pub const MH_DYLIB = 0x6;
pub const MH_BUNDLE = 0x8;

pub const LC_SEGMENT_64 = 0x19;
pub const LC_DYLIB = 0xc;
pub const LC_ID_DYLIB = 0xd;
pub const LC_LOAD_DYLIB = 0xc;

// ============================================================================
// Mach-O Header
// ============================================================================

pub const MachHeader64 = extern struct {
    magic: u32,
    cputype: i32,
    cpusubtype: i32,
    filetype: u32,
    ncmds: u32,
    sizeofcmds: u32,
    flags: u32,
    reserved: u32,
};

pub const LoadCommand = extern struct {
    cmd: u32,
    cmdsize: u32,
};

// ============================================================================
// Dylib Analysis
// ============================================================================

pub const DylibInfo = struct {
    name: []const u8,
    current_version: u32,
    compatibility_version: u32,
    timestamp: u32,
};

/// Parse a Mach-O dylib path
pub fn parseDylibPath(path: []const u8) DylibInfo {
    // Extract name from path
    var name = path;
    if (std.mem.lastIndexOf(u8, path, "/")) |idx| {
        name = path[idx + 1 ..];
    }

    return .{
        .name = name,
        .current_version = 0,
        .compatibility_version = 0,
        .timestamp = 0,
    };
}

/// Check if path looks like a framework
pub fn isFramework(path: []const u8) bool {
    return std.mem.indexOf(u8, path, ".framework/") != null;
}

/// Extract framework name
pub fn getFrameworkName(path: []const u8) ?[]const u8 {
    if (std.mem.indexOf(u8, path, ".framework/")) |idx| {
        // Find start of framework name
        var start = idx;
        while (start > 0 and path[start - 1] != '/') {
            start -= 1;
        }
        return path[start..idx];
    }
    return null;
}

// ============================================================================
// Library Path Resolution
// ============================================================================

/// macOS library search paths
pub fn getMacOSLibraryPaths() []const []const u8 {
    return &.{
        "/usr/lib",
        "/usr/local/lib",
        "/opt/homebrew/lib",
        "/System/Library/Frameworks",
        "/Library/Frameworks",
    };
}

/// Resolve @rpath, @executable_path, @loader_path
pub fn resolveAtPath(path: []const u8, context: []const u8) []const u8 {
    if (std.mem.startsWith(u8, path, "@rpath/")) {
        _ = context;
        return path[7..]; // Strip @rpath/
    }
    if (std.mem.startsWith(u8, path, "@executable_path/")) {
        return path[17..];
    }
    if (std.mem.startsWith(u8, path, "@loader_path/")) {
        return path[13..];
    }
    return path;
}

// ============================================================================
// Fat/Universal Binary
// ============================================================================

pub const FAT_MAGIC = 0xcafebabe;
pub const FAT_CIGAM = 0xbebafeca;

pub const FatHeader = extern struct {
    magic: u32,
    nfat_arch: u32,
};

pub const FatArch = extern struct {
    cputype: i32,
    cpusubtype: i32,
    offset: u32,
    size: u32,
    @"align": u32,
};

/// Check if file is a fat binary
pub fn isFatBinary(magic: u32) bool {
    return magic == FAT_MAGIC or magic == FAT_CIGAM;
}

/// Check if file is a Mach-O binary
pub fn isMachO(magic: u32) bool {
    return magic == MH_MAGIC or magic == MH_CIGAM or
        magic == MH_MAGIC_64 or magic == MH_CIGAM_64;
}

// ============================================================================
// Test Cases
// ============================================================================

fn testMachOConstants() !void {
    try std.testing.expectEqual(@as(u32, 0xfeedfacf), MH_MAGIC_64);
    try std.testing.expectEqual(@as(u32, 0xfeedface), MH_MAGIC);
    try std.testing.expectEqual(@as(u32, 0xcafebabe), FAT_MAGIC);
}

fn testParseDylibPath() !void {
    const info = parseDylibPath("/usr/lib/libSystem.B.dylib");
    try std.testing.expectEqualStrings("libSystem.B.dylib", info.name);
}

fn testIsFramework() !void {
    try std.testing.expect(isFramework("/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation"));
    try std.testing.expect(!isFramework("/usr/lib/libSystem.B.dylib"));
}

fn testGetFrameworkName() !void {
    const name = getFrameworkName("/System/Library/Frameworks/AppKit.framework/AppKit");
    try std.testing.expect(name != null);
    try std.testing.expectEqualStrings("AppKit", name.?);

    const none = getFrameworkName("/usr/lib/libz.dylib");
    try std.testing.expect(none == null);
}

fn testResolveAtPath() !void {
    try std.testing.expectEqualStrings("lib/libfoo.dylib", resolveAtPath("@rpath/lib/libfoo.dylib", "/app"));
    try std.testing.expectEqualStrings("../lib/libbar.dylib", resolveAtPath("@executable_path/../lib/libbar.dylib", "/app"));
    try std.testing.expectEqualStrings("/usr/lib/libz.dylib", resolveAtPath("/usr/lib/libz.dylib", "/app"));
}

fn testIsFatBinary() !void {
    try std.testing.expect(isFatBinary(FAT_MAGIC));
    try std.testing.expect(isFatBinary(FAT_CIGAM));
    try std.testing.expect(!isFatBinary(MH_MAGIC_64));
}

fn testIsMachO() !void {
    try std.testing.expect(isMachO(MH_MAGIC_64));
    try std.testing.expect(isMachO(MH_MAGIC));
    try std.testing.expect(isMachO(MH_CIGAM_64));
    try std.testing.expect(!isMachO(FAT_MAGIC));
    try std.testing.expect(!isMachO(0x7f454c46)); // ELF magic
}

fn testGetMacOSLibraryPaths() !void {
    const paths = getMacOSLibraryPaths();
    try std.testing.expect(paths.len > 0);
    try std.testing.expectEqualStrings("/usr/lib", paths[0]);
}

fn testMachHeader64Size() !void {
    try std.testing.expectEqual(@as(usize, 32), @sizeOf(MachHeader64));
}

fn testLoadCommandSize() !void {
    try std.testing.expectEqual(@as(usize, 8), @sizeOf(LoadCommand));
}

fn testFileTypes() !void {
    try std.testing.expect(MH_EXECUTE != MH_DYLIB);
    try std.testing.expect(MH_DYLIB != MH_BUNDLE);
}

fn testFatArchSize() !void {
    try std.testing.expectEqual(@as(usize, 20), @sizeOf(FatArch));
}

// ============================================================================
// Zig Test Declarations
// ============================================================================

test "macho_constants" {
    try testMachOConstants();
}

test "parse_dylib_path" {
    try testParseDylibPath();
}

test "is_framework" {
    try testIsFramework();
}

test "get_framework_name" {
    try testGetFrameworkName();
}

test "resolve_at_path" {
    try testResolveAtPath();
}

test "is_fat_binary" {
    try testIsFatBinary();
}

test "is_macho" {
    try testIsMachO();
}

test "get_macos_library_paths" {
    try testGetMacOSLibraryPaths();
}

test "mach_header_64_size" {
    try testMachHeader64Size();
}

test "load_command_size" {
    try testLoadCommandSize();
}

test "file_types" {
    try testFileTypes();
}

test "fat_arch_size" {
    try testFatArchSize();
}
