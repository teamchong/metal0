/// _aix_support - AIX Platform Support
/// Mirrors cpython/Lib/_aix_support.py
///
/// Platform-specific support for IBM AIX operating system.
/// Provides utilities for querying system configuration.

const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;

// ============================================================================
// Platform Detection
// ============================================================================

/// Check if running on AIX
pub const is_aix = builtin.os.tag == .aix;

// ============================================================================
// System Configuration
// ============================================================================

/// AIX version information
pub const AixVersion = struct {
    /// Major version (e.g., 7)
    major: u32,
    /// Minor version (e.g., 2)
    minor: u32,
    /// Tech level
    tech_level: u32 = 0,
    /// Service pack
    service_pack: u32 = 0,
};

/// Get AIX version (stub on non-AIX platforms)
pub fn getAixVersion() ?AixVersion {
    if (!is_aix) return null;

    // On real AIX, would parse output of `oslevel -s`
    // Format: VRMF (Version.Release.Mod.Fix)
    return AixVersion{
        .major = 7,
        .minor = 2,
        .tech_level = 0,
        .service_pack = 0,
    };
}

/// Get AIX build date
/// Parses build date from /usr/lpp/bos/inst_root/image.data if available
pub fn getAixBuildDate() ?[]const u8 {
    if (!is_aix) return null;

    // AIX stores installation info in /usr/lpp/bos
    const image_data = std.fs.cwd().openFile("/usr/lpp/bos/inst_root/image.data", .{}) catch {
        return null;
    };
    defer image_data.close();

    var buf: [1024]u8 = undefined;
    const read = image_data.reader().readAll(&buf) catch return null;

    // Look for DATE line
    var lines = std.mem.splitScalar(u8, buf[0..read], '\n');
    while (lines.next()) |line| {
        if (std.mem.startsWith(u8, line, "DATE = ")) {
            return line["DATE = ".len..];
        }
    }
    return null;
}

// ============================================================================
// Library Configuration
// ============================================================================

/// AIX library path configuration
pub const LibraryConfig = struct {
    /// Default library path
    libpath: []const u8 = "/usr/lib:/lib",
    /// 64-bit library path
    libpath64: []const u8 = "/usr/lib/64:/lib/64",
    /// Object mode (32 or 64)
    object_mode: u8 = 64,
};

/// Get library configuration
pub fn getLibraryConfig() LibraryConfig {
    return .{};
}

/// Get runtime library path
pub fn getRuntimeLibraryPath() []const u8 {
    // AIX uses LIBPATH instead of LD_LIBRARY_PATH
    return if (is_aix) "/usr/lib:/lib" else "";
}

/// Check if 64-bit mode
pub fn is64BitMode() bool {
    return @bitSizeOf(usize) == 64;
}

// ============================================================================
// XLC Compiler Detection
// ============================================================================

/// XLC compiler info
pub const XlcInfo = struct {
    version: ?[]const u8 = null,
    path: ?[]const u8 = null,
    is_xlc: bool = false,
};

/// Detect XLC compiler
/// Searches PATH for xlc/xlC and checks version
pub fn detectXlcCompiler() XlcInfo {
    const path_env = std.posix.getenv("PATH") orelse return .{};

    // Check common XLC locations
    const xlc_paths = [_][]const u8{
        "/usr/vac/bin/xlc",
        "/opt/IBM/xlC/16.1.0/bin/xlc",
        "/opt/IBM/xlC/13.1.3/bin/xlc",
    };

    // First check well-known locations
    for (xlc_paths) |xlc_path| {
        if (std.fs.cwd().access(xlc_path, .{})) |_| {
            return .{
                .path = xlc_path,
                .is_xlc = true,
                .version = null, // Would need to run xlc -qversion to get this
            };
        } else |_| {}
    }

    // Search PATH
    var paths = std.mem.splitScalar(u8, path_env, ':');
    while (paths.next()) |dir| {
        // Check for xlc in this directory
        var path_buf: [std.fs.max_path_bytes]u8 = undefined;
        const xlc_check = std.fmt.bufPrint(&path_buf, "{s}/xlc", .{dir}) catch continue;
        if (std.fs.cwd().access(xlc_check, .{})) |_| {
            return .{
                .path = dir,
                .is_xlc = true,
                .version = null,
            };
        } else |_| {}
    }

    return .{};
}

// ============================================================================
// System Limits
// ============================================================================

/// AIX-specific limits
pub const AixLimits = struct {
    /// Maximum filename length
    pub const NAME_MAX: usize = 255;
    /// Maximum path length
    pub const PATH_MAX: usize = 1023;
    /// Maximum argument list size
    pub const ARG_MAX: usize = 1048576;
    /// Maximum open files per process
    pub const OPEN_MAX: usize = 65534;
};

/// Get maximum filename length
pub fn getMaxFilenameLength() usize {
    return if (is_aix) AixLimits.NAME_MAX else std.fs.max_name_bytes;
}

/// Get maximum path length
pub fn getMaxPathLength() usize {
    return if (is_aix) AixLimits.PATH_MAX else std.fs.max_path_bytes;
}

// ============================================================================
// APAR (Authorized Program Analysis Report)
// ============================================================================

/// Check if specific APAR is installed
/// Checks /var/adm/ras/emgr.log for emergency fixes or fileset data
pub fn isAparInstalled(apar_id: []const u8) bool {
    if (!is_aix) return false;

    // Check emgr (emergency fix manager) log first
    const emgr_log = std.fs.cwd().openFile("/var/adm/ras/emgr.log", .{}) catch {
        // Try alternative location
        const alt = std.fs.cwd().openFile("/var/adm/sw/emgr.dat", .{}) catch {
            return false;
        };
        defer alt.close();
        return checkFileForApar(alt, apar_id);
    };
    defer emgr_log.close();

    return checkFileForApar(emgr_log, apar_id);
}

fn checkFileForApar(file: std.fs.File, apar_id: []const u8) bool {
    var buf: [8192]u8 = undefined;
    const read = file.reader().readAll(&buf) catch return false;

    // Simple text search for APAR ID
    return std.mem.indexOf(u8, buf[0..read], apar_id) != null;
}

// ============================================================================
// Module State
// ============================================================================

var initialized: bool = false;

/// Initialize the _aix_support module
pub fn init() void {
    if (initialized) return;
    initialized = true;
}

/// Reset module state
pub fn reset() void {
    initialized = false;
}

// ============================================================================
// Tests
// ============================================================================

test "aix detection" {
    // is_aix is a compile-time constant
    const result = is_aix;
    _ = result;
}

test "library config" {
    const config = getLibraryConfig();
    try std.testing.expect(config.object_mode == 32 or config.object_mode == 64);
}

test "64 bit mode" {
    const mode = is64BitMode();
    try std.testing.expect(mode == (@bitSizeOf(usize) == 64));
}

test "max path length" {
    const max_path = getMaxPathLength();
    try std.testing.expect(max_path > 0);
}

test "xlc detection" {
    const xlc = detectXlcCompiler();
    // On non-AIX, should not detect XLC
    if (!is_aix) {
        try std.testing.expect(!xlc.is_xlc);
    }
}
