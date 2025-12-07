/// perf_jit_trampoline - Perf JIT Trampoline
/// Mirrors cpython/Python/perf_jit_trampoline.c
///
/// Integration between JIT-compiled code and Linux perf profiler.
/// Generates DWARF debug info for JIT code to enable source-level profiling.

const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;

// ============================================================================
// Platform Support
// ============================================================================

/// Check if perf JIT trampolines are supported
pub const is_supported = builtin.os.tag == .linux;

// ============================================================================
// DWARF Debug Info
// ============================================================================

/// DWARF section types for JIT code
pub const DwarfSection = enum(u8) {
    debug_info = 0,
    debug_abbrev = 1,
    debug_line = 2,
    debug_str = 3,
    debug_ranges = 4,
};

/// DWARF compilation unit header
pub const CompUnitHeader = struct {
    /// Length of compilation unit (excluding length field)
    length: u32,
    /// DWARF version
    version: u16 = 4,
    /// Offset into .debug_abbrev
    abbrev_offset: u32 = 0,
    /// Address size
    address_size: u8 = 8,
};

/// DWARF line number program header
pub const LineNumberHeader = struct {
    /// Minimum instruction length
    min_inst_length: u8 = 1,
    /// Maximum ops per instruction
    max_ops_per_inst: u8 = 1,
    /// Default is_stmt
    default_is_stmt: bool = true,
    /// Line base for special opcodes
    line_base: i8 = -5,
    /// Line range for special opcodes
    line_range: u8 = 14,
    /// First special opcode
    opcode_base: u8 = 13,
};

// ============================================================================
// JIT Code Entry
// ============================================================================

/// Entry for JIT-compiled code
pub const JITCodeEntry = struct {
    /// Next entry in linked list
    next: ?*JITCodeEntry = null,
    /// Previous entry
    prev: ?*JITCodeEntry = null,
    /// Start address of code
    code_addr: usize,
    /// Size of code
    code_size: usize,
    /// Debug info (ELF image with DWARF)
    debug_info: []const u8,
    /// Function name
    name: []const u8,
    /// Source file
    file: ?[]const u8 = null,
    /// Line number
    line: u32 = 0,
    /// Registration timestamp
    timestamp: i64 = 0,
};

/// JIT descriptor for GDB/perf interface
pub const JITDescriptor = struct {
    /// Version (must be 1)
    version: u32 = 1,
    /// Action flag: 0=none, 1=register, 2=unregister
    action: u32 = 0,
    /// Head of code entry list
    first_entry: ?*JITCodeEntry = null,
    /// Tail of code entry list
    last_entry: ?*JITCodeEntry = null,
};

// ============================================================================
// Perf Map File
// ============================================================================

/// Perf map file writer for JIT code
pub const PerfJITMapWriter = struct {
    const Self = @This();

    /// File handle
    file: ?std.fs.File = null,
    /// Process ID
    pid: i32,
    /// Entry count
    count: usize = 0,
    /// Allocator
    allocator: Allocator,

    pub fn init(allocator: Allocator) Self {
        const pid: i32 = if (is_supported) std.os.linux.getpid() else 0;
        return Self{
            .allocator = allocator,
            .pid = pid,
        };
    }

    pub fn deinit(self: *Self) void {
        self.close();
    }

    /// Open the perf-jit map file
    pub fn open(self: *Self) !void {
        var buf: [128]u8 = undefined;
        const path = try std.fmt.bufPrint(&buf, "/tmp/perf-{d}.map", .{self.pid});
        self.file = try std.fs.cwd().createFile(path, .{ .truncate = false });
        // Seek to end for appending
        try self.file.?.seekFromEnd(0);
    }

    /// Close the file
    pub fn close(self: *Self) void {
        if (self.file) |f| {
            f.close();
            self.file = null;
        }
    }

    /// Write JIT code entry
    pub fn writeEntry(self: *Self, entry: *const JITCodeEntry) !void {
        if (self.file == null) {
            try self.open();
        }

        const writer = self.file.?.writer();

        // Format: <start_addr> <size> <name>
        try writer.print("{x} {x} {s}", .{
            entry.code_addr,
            entry.code_size,
            entry.name,
        });

        // Add source location if available
        if (entry.file) |file| {
            try writer.print(" {s}:{d}", .{ file, entry.line });
        }

        try writer.writeByte('\n');
        self.count += 1;
    }

    /// Flush to disk
    pub fn flush(self: *Self) void {
        if (self.file) |f| {
            f.sync() catch {};
        }
    }
};

// ============================================================================
// JIT Dump File
// ============================================================================

/// JIT dump file header (for perf inject -j)
pub const JITDumpHeader = struct {
    /// Magic number
    magic: u32 = 0x4A695444, // "JiTD"
    /// Version
    version: u32 = 1,
    /// Total size of header
    total_size: u32 = 40,
    /// ELF machine type
    elf_mach: u32 = 0x3E, // x86_64
    /// Padding
    pad1: u32 = 0,
    /// Process ID
    pid: u32,
    /// Timestamp
    timestamp: u64,
    /// Flags
    flags: u64 = 0,
};

/// JIT dump record types
pub const JITRecordType = enum(u32) {
    load = 0,
    move = 1,
    debug_info = 2,
    close = 3,
    unwinding = 4,
};

/// JIT dump record header
pub const JITRecordHeader = struct {
    /// Record type
    record_type: JITRecordType,
    /// Total size including header
    total_size: u32,
    /// Timestamp
    timestamp: u64,
};

/// JIT load record
pub const JITLoadRecord = struct {
    /// Unique code ID
    code_id: u64,
    /// Code address
    code_addr: usize,
    /// Code size
    code_size: usize,
};

// ============================================================================
// Trampoline Manager
// ============================================================================

/// Manages perf JIT trampolines
pub const PerfJITManager = struct {
    const Self = @This();

    /// Registered code entries
    entries: std.ArrayList(*JITCodeEntry),
    /// Map writer
    map_writer: PerfJITMapWriter,
    /// JIT descriptor (for GDB interface)
    descriptor: JITDescriptor = .{},
    /// Next code ID
    next_code_id: u64 = 1,
    /// Is active
    active: bool = false,
    /// Allocator
    allocator: Allocator,

    pub fn init(allocator: Allocator) Self {
        return Self{
            .allocator = allocator,
            .entries = std.ArrayList(*JITCodeEntry).init(allocator),
            .map_writer = PerfJITMapWriter.init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        // Free all entries
        for (self.entries.items) |entry| {
            self.allocator.free(entry.debug_info);
            self.allocator.destroy(entry);
        }
        self.entries.deinit();
        self.map_writer.deinit();
    }

    /// Start trampoline collection
    pub fn start(self: *Self) !void {
        if (self.active) return;
        try self.map_writer.open();
        self.active = true;
    }

    /// Stop trampoline collection
    pub fn stop(self: *Self) void {
        if (!self.active) return;
        self.map_writer.flush();
        self.map_writer.close();
        self.active = false;
    }

    /// Register JIT-compiled code
    pub fn registerCode(
        self: *Self,
        code_addr: usize,
        code_size: usize,
        name: []const u8,
        file: ?[]const u8,
        line: u32,
    ) !*JITCodeEntry {
        // Create entry
        const entry = try self.allocator.create(JITCodeEntry);
        entry.* = .{
            .code_addr = code_addr,
            .code_size = code_size,
            .name = name,
            .file = file,
            .line = line,
            .debug_info = try self.generateDebugInfo(code_addr, code_size, name, file, line),
            .timestamp = std.time.timestamp(),
        };

        // Link into list
        entry.prev = self.descriptor.last_entry;
        if (self.descriptor.last_entry) |last| {
            last.next = entry;
        }
        self.descriptor.last_entry = entry;
        if (self.descriptor.first_entry == null) {
            self.descriptor.first_entry = entry;
        }

        try self.entries.append(entry);

        // Write to map file if active
        if (self.active) {
            try self.map_writer.writeEntry(entry);
        }

        // Signal GDB
        self.descriptor.action = 1; // register
        self.notifyDebugger();

        return entry;
    }

    /// Unregister JIT code
    pub fn unregisterCode(self: *Self, entry: *JITCodeEntry) void {
        // Unlink from list
        if (entry.prev) |prev| {
            prev.next = entry.next;
        } else {
            self.descriptor.first_entry = entry.next;
        }
        if (entry.next) |next| {
            next.prev = entry.prev;
        } else {
            self.descriptor.last_entry = entry.prev;
        }

        // Signal GDB
        self.descriptor.action = 2; // unregister
        self.notifyDebugger();

        // Remove from our list
        for (self.entries.items, 0..) |e, i| {
            if (e == entry) {
                _ = self.entries.swapRemove(i);
                break;
            }
        }

        // Free entry
        self.allocator.free(entry.debug_info);
        self.allocator.destroy(entry);
    }

    /// Generate minimal debug info for entry
    fn generateDebugInfo(
        self: *Self,
        code_addr: usize,
        code_size: usize,
        name: []const u8,
        file: ?[]const u8,
        line: u32,
    ) ![]const u8 {
        _ = code_addr;
        _ = code_size;
        _ = file;
        _ = line;

        // Placeholder - would generate real DWARF/ELF
        const debug = try self.allocator.alloc(u8, name.len + 32);
        @memset(debug, 0);
        @memcpy(debug[0..name.len], name);
        return debug;
    }

    /// Notify debugger of changes (GDB JIT interface)
    fn notifyDebugger(self: *Self) void {
        _ = self;
        // In real implementation, would call __jit_debug_register_code()
        // which is a noop that GDB breakpoints on
    }

    /// Get number of registered entries
    pub fn getCount(self: *const Self) usize {
        return self.entries.items.len;
    }
};

// ============================================================================
// Module State
// ============================================================================

var initialized: bool = false;
var global_manager: ?PerfJITManager = null;

/// Initialize the perf_jit_trampoline module
pub fn init() void {
    if (initialized) return;
    initialized = true;
}

/// Get global manager
pub fn getManager(allocator: Allocator) *PerfJITManager {
    if (global_manager == null) {
        global_manager = PerfJITManager.init(allocator);
    }
    return &global_manager.?;
}

/// Enable perf JIT trampolines
pub fn enable(allocator: Allocator) !void {
    var manager = getManager(allocator);
    try manager.start();
}

/// Disable perf JIT trampolines
pub fn disable(allocator: Allocator) void {
    var manager = getManager(allocator);
    manager.stop();
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

test "jit descriptor" {
    const desc = JITDescriptor{};
    try std.testing.expectEqual(@as(u32, 1), desc.version);
    try std.testing.expect(desc.first_entry == null);
}

test "jit code entry" {
    const entry = JITCodeEntry{
        .code_addr = 0x1000,
        .code_size = 0x100,
        .debug_info = &[_]u8{},
        .name = "test_func",
    };
    try std.testing.expectEqual(@as(usize, 0x1000), entry.code_addr);
}

test "perf jit manager" {
    const allocator = std.testing.allocator;
    var manager = PerfJITManager.init(allocator);
    defer manager.deinit();

    try std.testing.expect(!manager.active);
    try std.testing.expectEqual(@as(usize, 0), manager.getCount());
}

test "comp unit header" {
    const header = CompUnitHeader{
        .length = 100,
    };
    try std.testing.expectEqual(@as(u16, 4), header.version);
    try std.testing.expectEqual(@as(u8, 8), header.address_size);
}

test "jit dump header" {
    const header = JITDumpHeader{
        .pid = 1234,
        .timestamp = 0,
    };
    try std.testing.expectEqual(@as(u32, 0x4A695444), header.magic);
    try std.testing.expectEqual(@as(u32, 1), header.version);
}

test "jit record types" {
    try std.testing.expectEqual(@as(u32, 0), @intFromEnum(JITRecordType.load));
    try std.testing.expectEqual(@as(u32, 2), @intFromEnum(JITRecordType.debug_info));
}
