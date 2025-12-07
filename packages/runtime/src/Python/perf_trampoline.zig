/// perf_trampoline - Perf Trampoline
/// Mirrors cpython/Python/perf_trampoline.c
///
/// Support for Linux perf profiler integration.
/// Creates trampolines with debug info for profiler symbolization.

const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;

// ============================================================================
// Platform Support
// ============================================================================

/// Check if perf trampolines are supported
pub const is_supported = builtin.os.tag == .linux;

// ============================================================================
// Trampoline Configuration
// ============================================================================

/// Perf trampoline configuration
pub const PerfConfig = struct {
    /// Enable perf trampolines
    enabled: bool = false,
    /// Output directory for perf map files
    map_dir: []const u8 = "/tmp",
    /// Include line numbers
    include_lines: bool = true,
    /// Include column offsets
    include_columns: bool = false,
    /// Maximum entries in map file
    max_entries: usize = 100000,
};

/// Default configuration
pub const default_config = PerfConfig{};

// ============================================================================
// Perf Map Entry
// ============================================================================

/// Entry in perf map file
pub const PerfMapEntry = struct {
    /// Start address of code region
    start_addr: usize,
    /// Size of code region
    size: usize,
    /// Symbol name
    name: []const u8,
    /// Source file (optional)
    file: ?[]const u8 = null,
    /// Line number (optional)
    line: ?u32 = null,
};

/// Perf map writer
pub const PerfMapWriter = struct {
    const Self = @This();

    /// File for writing map entries
    file: ?std.fs.File = null,
    /// Entry count
    count: usize = 0,
    /// Max entries
    max_entries: usize,
    /// Allocator
    allocator: Allocator,

    pub fn init(allocator: Allocator, max_entries: usize) Self {
        return Self{
            .allocator = allocator,
            .max_entries = max_entries,
        };
    }

    pub fn deinit(self: *Self) void {
        if (self.file) |f| {
            f.close();
        }
    }

    /// Open the perf map file
    pub fn open(self: *Self, pid: i32) !void {
        var buf: [64]u8 = undefined;
        const path = try std.fmt.bufPrint(&buf, "/tmp/perf-{d}.map", .{pid});

        self.file = try std.fs.cwd().createFile(path, .{ .truncate = true });
    }

    /// Write an entry to the map file
    pub fn writeEntry(self: *Self, entry: PerfMapEntry) !void {
        if (self.file == null) return;
        if (self.count >= self.max_entries) return;

        const writer = self.file.?.writer();

        // Format: <start> <size> <name>
        try writer.print("{x} {x} {s}", .{ entry.start_addr, entry.size, entry.name });

        // Optional file:line info
        if (entry.file) |file| {
            try writer.print(" {s}", .{file});
            if (entry.line) |line| {
                try writer.print(":{d}", .{line});
            }
        }

        try writer.writeByte('\n');
        self.count += 1;
    }

    /// Flush the map file
    pub fn flush(self: *Self) void {
        if (self.file) |f| {
            f.sync() catch {};
        }
    }
};

// ============================================================================
// Trampoline Manager
// ============================================================================

/// Manages perf trampolines for Python functions
pub const TrampolineManager = struct {
    const Self = @This();

    /// Configuration
    config: PerfConfig,
    /// Map writer
    map_writer: PerfMapWriter,
    /// Registered trampolines
    trampolines: std.ArrayList(TrampolineInfo),
    /// Is active
    active: bool = false,
    /// Allocator
    allocator: Allocator,

    pub fn init(allocator: Allocator, config: PerfConfig) Self {
        return Self{
            .allocator = allocator,
            .config = config,
            .map_writer = PerfMapWriter.init(allocator, config.max_entries),
            .trampolines = std.ArrayList(TrampolineInfo).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.map_writer.deinit();
        self.trampolines.deinit();
    }

    /// Start collecting perf data
    pub fn start(self: *Self) !void {
        if (!self.config.enabled) return;
        if (self.active) return;

        // Get current PID
        const pid: i32 = if (is_supported) std.os.linux.getpid() else 0;
        try self.map_writer.open(pid);
        self.active = true;
    }

    /// Stop collecting
    pub fn stop(self: *Self) void {
        if (!self.active) return;
        self.map_writer.flush();
        self.active = false;
    }

    /// Register a trampoline for a Python function
    pub fn registerTrampoline(self: *Self, info: TrampolineInfo) !void {
        try self.trampolines.append(info);

        if (self.active) {
            try self.map_writer.writeEntry(.{
                .start_addr = info.code_addr,
                .size = info.code_size,
                .name = info.name,
                .file = info.file,
                .line = info.line,
            });
        }
    }

    /// Get number of registered trampolines
    pub fn getCount(self: *const Self) usize {
        return self.trampolines.items.len;
    }
};

/// Information about a trampoline
pub const TrampolineInfo = struct {
    /// Code address
    code_addr: usize,
    /// Code size
    code_size: usize,
    /// Function name
    name: []const u8,
    /// Source file
    file: ?[]const u8 = null,
    /// Line number
    line: ?u32 = null,
    /// Code object ID
    code_id: u64 = 0,
};

// ============================================================================
// Symbol Generation
// ============================================================================

/// Generate symbol name for a Python function
pub fn generateSymbol(
    allocator: Allocator,
    module: []const u8,
    qualname: []const u8,
    lineno: u32,
) ![]const u8 {
    if (qualname.len == 0) {
        return try std.fmt.allocPrint(allocator, "py::{s}:<module>:{d}", .{ module, lineno });
    }
    return try std.fmt.allocPrint(allocator, "py::{s}:{s}:{d}", .{ module, qualname, lineno });
}

/// Parse a perf symbol back to components
pub fn parseSymbol(symbol: []const u8) ?struct {
    module: []const u8,
    qualname: []const u8,
    lineno: u32,
} {
    if (!std.mem.startsWith(u8, symbol, "py::")) return null;

    const rest = symbol[4..];
    var parts = std.mem.splitScalar(u8, rest, ':');

    const module = parts.next() orelse return null;
    const qualname = parts.next() orelse return null;
    const lineno_str = parts.next() orelse return null;

    const lineno = std.fmt.parseInt(u32, lineno_str, 10) catch return null;

    return .{
        .module = module,
        .qualname = qualname,
        .lineno = lineno,
    };
}

// ============================================================================
// Module State
// ============================================================================

var initialized: bool = false;
var global_manager: ?TrampolineManager = null;

/// Initialize the perf_trampoline module
pub fn init() void {
    if (initialized) return;
    initialized = true;
}

/// Get global manager
pub fn getManager(allocator: Allocator) *TrampolineManager {
    if (global_manager == null) {
        global_manager = TrampolineManager.init(allocator, default_config);
    }
    return &global_manager.?;
}

/// Enable perf trampolines
pub fn enable(allocator: Allocator) !void {
    var manager = getManager(allocator);
    manager.config.enabled = true;
    try manager.start();
}

/// Disable perf trampolines
pub fn disable(allocator: Allocator) void {
    var manager = getManager(allocator);
    manager.stop();
    manager.config.enabled = false;
}

/// Reset module state
pub fn reset() void {
    if (global_manager) |*manager| {
        manager.deinit();
    }
    global_manager = null;
    initialized = false;
}

// ============================================================================
// Tests
// ============================================================================

test "perf config defaults" {
    const config = PerfConfig{};
    try std.testing.expect(!config.enabled);
    try std.testing.expectEqualStrings("/tmp", config.map_dir);
}

test "trampoline manager init" {
    const allocator = std.testing.allocator;
    var manager = TrampolineManager.init(allocator, .{});
    defer manager.deinit();

    try std.testing.expect(!manager.active);
    try std.testing.expectEqual(@as(usize, 0), manager.getCount());
}

test "register trampoline" {
    const allocator = std.testing.allocator;
    var manager = TrampolineManager.init(allocator, .{});
    defer manager.deinit();

    try manager.registerTrampoline(.{
        .code_addr = 0x1000,
        .code_size = 0x100,
        .name = "test_func",
    });

    try std.testing.expectEqual(@as(usize, 1), manager.getCount());
}

test "generate symbol" {
    const allocator = std.testing.allocator;

    const sym1 = try generateSymbol(allocator, "mymodule", "func", 42);
    defer allocator.free(sym1);
    try std.testing.expectEqualStrings("py::mymodule:func:42", sym1);

    const sym2 = try generateSymbol(allocator, "mymodule", "", 1);
    defer allocator.free(sym2);
    try std.testing.expectEqualStrings("py::mymodule:<module>:1", sym2);
}

test "parse symbol" {
    const result = parseSymbol("py::mymodule:func:42");
    try std.testing.expect(result != null);
    try std.testing.expectEqualStrings("mymodule", result.?.module);
    try std.testing.expectEqualStrings("func", result.?.qualname);
    try std.testing.expectEqual(@as(u32, 42), result.?.lineno);

    try std.testing.expect(parseSymbol("not_a_py_symbol") == null);
}

test "perf map entry" {
    const entry = PerfMapEntry{
        .start_addr = 0x1000,
        .size = 0x100,
        .name = "test",
    };
    try std.testing.expectEqual(@as(usize, 0x1000), entry.start_addr);
}
