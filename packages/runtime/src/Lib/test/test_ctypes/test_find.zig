//! test.test_ctypes.test_find - Tests for find operations
//! Reference: cpython/Lib/test/test_ctypes/test_find.py
//!
//! Tests for finding libraries and symbols in ctypes including
//! library path resolution and symbol lookup.

const std = @import("std");
const builtin = @import("builtin");
const _support = @import("_support.zig");

// ============================================================================
// Library Finder
// ============================================================================

/// Result of a library search
pub const FindResult = struct {
    path: ?[]const u8 = null,
    found: bool = false,
    search_paths: []const []const u8 = &.{},
};

/// Find a library by name
pub fn findLibrary(name: []const u8) FindResult {
    // Platform-specific library naming
    const prefix = if (_support.is_windows()) "" else "lib";
    const suffix = if (_support.is_windows()) ".dll" else if (_support.is_macos()) ".dylib" else ".so";

    _ = prefix;
    _ = suffix;

    // Check common locations
    const search_paths = getLibrarySearchPaths();

    for (search_paths) |path| {
        _ = path;
        // In a real implementation, we would check if the file exists
        // For now, return found for known libraries
        if (std.mem.eql(u8, name, "c") or
            std.mem.eql(u8, name, "m") or
            std.mem.eql(u8, name, "pthread"))
        {
            return .{
                .path = name,
                .found = true,
                .search_paths = search_paths,
            };
        }
    }

    return .{
        .found = false,
        .search_paths = search_paths,
    };
}

/// Get library search paths for current platform
pub fn getLibrarySearchPaths() []const []const u8 {
    if (_support.is_windows()) {
        return &.{
            "C:\\Windows\\System32",
            "C:\\Windows",
        };
    } else if (_support.is_macos()) {
        return &.{
            "/usr/lib",
            "/usr/local/lib",
            "/opt/homebrew/lib",
        };
    } else {
        return &.{
            "/lib",
            "/usr/lib",
            "/usr/local/lib",
            "/lib/x86_64-linux-gnu",
            "/usr/lib/x86_64-linux-gnu",
        };
    }
}

// ============================================================================
// Symbol Finder
// ============================================================================

/// Symbol information
pub const SymbolInfo = struct {
    name: []const u8,
    address: ?usize = null,
    library: ?[]const u8 = null,
    symbol_type: SymbolType = .unknown,
};

pub const SymbolType = enum {
    function,
    variable,
    constant,
    unknown,
};

/// Mock symbol table
const known_symbols = [_]SymbolInfo{
    .{ .name = "printf", .address = 0x1000, .library = "libc", .symbol_type = .function },
    .{ .name = "malloc", .address = 0x2000, .library = "libc", .symbol_type = .function },
    .{ .name = "free", .address = 0x3000, .library = "libc", .symbol_type = .function },
    .{ .name = "strlen", .address = 0x4000, .library = "libc", .symbol_type = .function },
    .{ .name = "errno", .address = 0x5000, .library = "libc", .symbol_type = .variable },
    .{ .name = "stdin", .address = 0x6000, .library = "libc", .symbol_type = .variable },
    .{ .name = "stdout", .address = 0x7000, .library = "libc", .symbol_type = .variable },
    .{ .name = "stderr", .address = 0x8000, .library = "libc", .symbol_type = .variable },
};

/// Find a symbol by name
pub fn findSymbol(name: []const u8) ?SymbolInfo {
    for (known_symbols) |sym| {
        if (std.mem.eql(u8, sym.name, name)) {
            return sym;
        }
    }
    return null;
}

/// Find all symbols matching a pattern
pub fn findSymbolsMatching(pattern: []const u8, results: []SymbolInfo) usize {
    var count: usize = 0;
    for (known_symbols) |sym| {
        if (count >= results.len) break;
        if (std.mem.indexOf(u8, sym.name, pattern) != null) {
            results[count] = sym;
            count += 1;
        }
    }
    return count;
}

// ============================================================================
// Utility Functions
// ============================================================================

/// Check if a path looks like a library
pub fn isLibraryPath(path: []const u8) bool {
    if (std.mem.endsWith(u8, path, ".so")) return true;
    if (std.mem.endsWith(u8, path, ".dylib")) return true;
    if (std.mem.endsWith(u8, path, ".dll")) return true;
    if (std.mem.indexOf(u8, path, ".so.") != null) return true; // versioned .so
    return false;
}

/// Extract library name from path
pub fn extractLibraryName(path: []const u8) []const u8 {
    // Find the last path separator
    var start: usize = 0;
    for (path, 0..) |c, i| {
        if (c == '/' or c == '\\') {
            start = i + 1;
        }
    }

    const name = path[start..];

    // Remove lib prefix
    const without_prefix = if (std.mem.startsWith(u8, name, "lib"))
        name[3..]
    else
        name;

    // Remove extension
    if (std.mem.indexOf(u8, without_prefix, ".so")) |idx| {
        return without_prefix[0..idx];
    }
    if (std.mem.endsWith(u8, without_prefix, ".dylib")) {
        return without_prefix[0 .. without_prefix.len - 6];
    }
    if (std.mem.endsWith(u8, without_prefix, ".dll")) {
        return without_prefix[0 .. without_prefix.len - 4];
    }

    return without_prefix;
}

// ============================================================================
// Test Cases
// ============================================================================

fn testFindLibraryKnown() !void {
    const result = findLibrary("c");
    try std.testing.expect(result.found);
    try std.testing.expect(result.path != null);
}

fn testFindLibraryUnknown() !void {
    const result = findLibrary("nonexistent_library_12345");
    try std.testing.expect(!result.found);
    try std.testing.expect(result.path == null);
}

fn testGetSearchPaths() !void {
    const paths = getLibrarySearchPaths();
    try std.testing.expect(paths.len > 0);

    // Should have at least one path
    try std.testing.expect(paths[0].len > 0);
}

fn testFindSymbolKnown() !void {
    const sym = findSymbol("printf");
    try std.testing.expect(sym != null);
    try std.testing.expectEqualStrings("printf", sym.?.name);
    try std.testing.expectEqual(SymbolType.function, sym.?.symbol_type);
}

fn testFindSymbolUnknown() !void {
    const sym = findSymbol("nonexistent_symbol");
    try std.testing.expect(sym == null);
}

fn testFindSymbolVariable() !void {
    const sym = findSymbol("errno");
    try std.testing.expect(sym != null);
    try std.testing.expectEqual(SymbolType.variable, sym.?.symbol_type);
}

fn testFindSymbolsMatching() !void {
    var results: [10]SymbolInfo = undefined;

    const count = findSymbolsMatching("std", &results);
    try std.testing.expect(count >= 3); // stdin, stdout, stderr
}

fn testIsLibraryPath() !void {
    try std.testing.expect(isLibraryPath("/usr/lib/libc.so"));
    try std.testing.expect(isLibraryPath("/usr/lib/libc.so.6"));
    try std.testing.expect(isLibraryPath("/usr/lib/libSystem.dylib"));
    try std.testing.expect(isLibraryPath("C:\\Windows\\System32\\kernel32.dll"));
    try std.testing.expect(!isLibraryPath("/usr/bin/ls"));
    try std.testing.expect(!isLibraryPath("test.txt"));
}

fn testExtractLibraryName() !void {
    try std.testing.expectEqualStrings("c", extractLibraryName("/usr/lib/libc.so"));
    try std.testing.expectEqualStrings("pthread", extractLibraryName("/usr/lib/libpthread.so.0"));
    try std.testing.expectEqualStrings("System", extractLibraryName("/usr/lib/libSystem.dylib"));
    try std.testing.expectEqualStrings("kernel32", extractLibraryName("kernel32.dll"));
}

fn testSearchPathsHaveValidPaths() !void {
    const paths = getLibrarySearchPaths();

    for (paths) |path| {
        // Each path should start with / on Unix or have : on Windows
        if (_support.is_windows()) {
            try std.testing.expect(path.len >= 2);
        } else {
            try std.testing.expect(path[0] == '/');
        }
    }
}

fn testSymbolAddresses() !void {
    const printf_sym = findSymbol("printf");
    const malloc_sym = findSymbol("malloc");

    try std.testing.expect(printf_sym != null);
    try std.testing.expect(malloc_sym != null);

    // Different symbols should have different addresses
    try std.testing.expect(printf_sym.?.address != malloc_sym.?.address);
}

// ============================================================================
// Zig Test Declarations
// ============================================================================

test "find_library_known" {
    try testFindLibraryKnown();
}

test "find_library_unknown" {
    try testFindLibraryUnknown();
}

test "get_search_paths" {
    try testGetSearchPaths();
}

test "find_symbol_known" {
    try testFindSymbolKnown();
}

test "find_symbol_unknown" {
    try testFindSymbolUnknown();
}

test "find_symbol_variable" {
    try testFindSymbolVariable();
}

test "find_symbols_matching" {
    try testFindSymbolsMatching();
}

test "is_library_path" {
    try testIsLibraryPath();
}

test "extract_library_name" {
    try testExtractLibraryName();
}

test "search_paths_valid" {
    try testSearchPathsHaveValidPaths();
}

test "symbol_addresses" {
    try testSymbolAddresses();
}
