/// getcompiler - Compiler Identification
/// Mirrors cpython/Python/getcompiler.c
///
/// Returns the compiler identification string

const std = @import("std");
const builtin = @import("builtin");

// ============================================================================
// Compiler String
// ============================================================================

/// Get the compiler identification string
/// Format: "[CompilerName version]"
pub fn getCompiler() []const u8 {
    // Zig compiler info at comptime
    return comptime blk: {
        const zig_version = builtin.zig_version;
        break :blk std.fmt.comptimePrint(
            "[Zig {d}.{d}.{d}]",
            .{ zig_version.major, zig_version.minor, zig_version.patch },
        );
    };
}

/// Get raw Zig version
pub fn getZigVersion() std.SemanticVersion {
    return builtin.zig_version;
}

/// Get Zig version string
pub fn getZigVersionString() []const u8 {
    return comptime blk: {
        const v = builtin.zig_version;
        break :blk std.fmt.comptimePrint("{d}.{d}.{d}", .{ v.major, v.minor, v.patch });
    };
}

// ============================================================================
// Build Information
// ============================================================================

/// Get build mode string
pub fn getBuildMode() []const u8 {
    return switch (builtin.mode) {
        .Debug => "debug",
        .ReleaseSafe => "release-safe",
        .ReleaseFast => "release-fast",
        .ReleaseSmall => "release-small",
    };
}

/// Check if debug build
pub fn isDebugBuild() bool {
    return builtin.mode == .Debug;
}

/// Check if release build
pub fn isReleaseBuild() bool {
    return builtin.mode != .Debug;
}

/// Check if optimized
pub fn isOptimized() bool {
    return builtin.mode == .ReleaseFast or builtin.mode == .ReleaseSmall;
}

// ============================================================================
// Target Information
// ============================================================================

/// Get target triple
pub fn getTargetTriple() []const u8 {
    return comptime blk: {
        const arch = @tagName(builtin.cpu.arch);
        const os = @tagName(builtin.os.tag);
        const abi = @tagName(builtin.abi);
        break :blk arch ++ "-" ++ os ++ "-" ++ abi;
    };
}

/// Get target OS
pub fn getTargetOS() []const u8 {
    return @tagName(builtin.os.tag);
}

/// Get target architecture
pub fn getTargetArch() []const u8 {
    return @tagName(builtin.cpu.arch);
}

/// Get target ABI
pub fn getTargetABI() []const u8 {
    return @tagName(builtin.abi);
}

// ============================================================================
// CPU Features
// ============================================================================

/// Check if CPU has specific feature
pub fn hasCpuFeature(feature: []const u8) bool {
    inline for (std.meta.fields(@TypeOf(builtin.cpu.features))) |field| {
        if (std.mem.eql(u8, field.name, feature)) {
            return @field(builtin.cpu.features, field.name);
        }
    }
    return false;
}

/// Get CPU model name
pub fn getCpuModel() []const u8 {
    return builtin.cpu.model.name;
}

// ============================================================================
// Compile-time Information
// ============================================================================

/// Get whether single-threaded
pub fn isSingleThreaded() bool {
    return builtin.single_threaded;
}

/// Get whether link-time optimization is enabled
pub fn isLTO() bool {
    // LTO status isn't directly exposed, check optimization mode
    return builtin.mode == .ReleaseFast or builtin.mode == .ReleaseSmall;
}

/// Get object format
pub fn getObjectFormat() []const u8 {
    return @tagName(builtin.object_format);
}

// ============================================================================
// Full Build Information
// ============================================================================

/// Get comprehensive build info string
pub fn getBuildInfo() []const u8 {
    return comptime blk: {
        const zig_ver = getZigVersionString();
        const mode = getBuildMode();
        const triple = getTargetTriple();
        break :blk std.fmt.comptimePrint(
            "Zig {s} ({s}) {s}",
            .{ zig_ver, mode, triple },
        );
    };
}

// ============================================================================
// Initialization
// ============================================================================

pub fn init() void {}

// ============================================================================
// Tests
// ============================================================================

test "compiler string format" {
    const compiler = getCompiler();
    try std.testing.expect(compiler.len > 0);
    try std.testing.expect(std.mem.startsWith(u8, compiler, "[Zig"));
    try std.testing.expect(std.mem.endsWith(u8, compiler, "]"));
}

test "zig version" {
    const version = getZigVersion();
    try std.testing.expect(version.major >= 0);

    const version_str = getZigVersionString();
    try std.testing.expect(version_str.len >= 5); // "0.0.0"
}

test "build mode" {
    const mode = getBuildMode();
    try std.testing.expect(mode.len > 0);

    const known = [_][]const u8{ "debug", "release-safe", "release-fast", "release-small" };
    var found = false;
    for (known) |m| {
        if (std.mem.eql(u8, mode, m)) {
            found = true;
            break;
        }
    }
    try std.testing.expect(found);
}

test "target triple" {
    const triple = getTargetTriple();
    try std.testing.expect(triple.len > 0);

    // Should contain dashes
    try std.testing.expect(std.mem.count(u8, triple, "-") >= 2);
}

test "cpu model" {
    const model = getCpuModel();
    try std.testing.expect(model.len > 0);
}

test "build info" {
    const info = getBuildInfo();
    try std.testing.expect(info.len > 0);
    try std.testing.expect(std.mem.indexOf(u8, info, "Zig") != null);
}
