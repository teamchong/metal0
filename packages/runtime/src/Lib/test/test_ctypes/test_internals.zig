//! test.test_ctypes.test_internals - Tests for internal operations
//! Reference: cpython/Lib/test/test_ctypes/test_internals.py
//!
//! Tests for ctypes internal implementation details including
//! memory management, type system, and low-level operations.

const std = @import("std");
const _support = @import("_support.zig");

// ============================================================================
// Internal Memory Management
// ============================================================================

/// Allocator wrapper for ctypes memory
pub const CTypesAllocator = struct {
    const Self = @This();

    backing: std.mem.Allocator,
    total_allocated: usize = 0,
    allocation_count: usize = 0,
    deallocation_count: usize = 0,

    pub fn init(backing: std.mem.Allocator) Self {
        return .{ .backing = backing };
    }

    pub fn alloc(self: *Self, size: usize) ![]u8 {
        const mem = try self.backing.alloc(u8, size);
        self.total_allocated += size;
        self.allocation_count += 1;
        return mem;
    }

    pub fn free(self: *Self, ptr: []u8) void {
        self.backing.free(ptr);
        self.deallocation_count += 1;
    }

    pub fn stats(self: *const Self) AllocStats {
        return .{
            .total_allocated = self.total_allocated,
            .allocation_count = self.allocation_count,
            .deallocation_count = self.deallocation_count,
        };
    }
};

pub const AllocStats = struct {
    total_allocated: usize,
    allocation_count: usize,
    deallocation_count: usize,
};

// ============================================================================
// Type Registry
// ============================================================================

/// Registry for ctypes type information
pub const TypeRegistry = struct {
    const Self = @This();
    const max_types = 64;

    types: [max_types]?TypeEntry = [_]?TypeEntry{null} ** max_types,
    count: usize = 0,

    pub fn init() Self {
        return .{};
    }

    pub fn register(self: *Self, name: []const u8, size: usize, alignment: usize) !u32 {
        if (self.count >= max_types) {
            return error.RegistryFull;
        }

        const id = @as(u32, @intCast(self.count));
        self.types[self.count] = .{
            .id = id,
            .name = name,
            .size = size,
            .alignment = alignment,
        };
        self.count += 1;
        return id;
    }

    pub fn lookup(self: *const Self, id: u32) ?TypeEntry {
        if (id >= self.count) return null;
        return self.types[id];
    }

    pub fn lookupByName(self: *const Self, name: []const u8) ?TypeEntry {
        for (self.types[0..self.count]) |entry| {
            if (entry) |e| {
                if (std.mem.eql(u8, e.name, name)) {
                    return e;
                }
            }
        }
        return null;
    }
};

pub const TypeEntry = struct {
    id: u32,
    name: []const u8,
    size: usize,
    alignment: usize,
};

// ============================================================================
// Object Header
// ============================================================================

/// Internal object header for ctypes objects
pub const ObjectHeader = struct {
    const Self = @This();

    type_id: u32 = 0,
    ref_count: u32 = 1,
    flags: ObjectFlags = .{},

    pub fn init(type_id: u32) Self {
        return .{ .type_id = type_id };
    }

    pub fn incRef(self: *Self) void {
        self.ref_count +|= 1;
    }

    pub fn decRef(self: *Self) bool {
        self.ref_count -|= 1;
        return self.ref_count == 0;
    }
};

pub const ObjectFlags = packed struct {
    is_pointer: bool = false,
    is_array: bool = false,
    owns_memory: bool = true,
    is_readonly: bool = false,
    _reserved: u4 = 0,
};

// ============================================================================
// Buffer Protocol
// ============================================================================

/// Buffer information structure
pub const BufferInfo = struct {
    ptr: ?*anyopaque = null,
    len: usize = 0,
    itemsize: usize = 1,
    format: []const u8 = "B",
    ndim: u8 = 1,
    shape: ?[*]usize = null,
    strides: ?[*]isize = null,
    readonly: bool = false,

    pub fn isContiguous(self: *const Self) bool {
        if (self.ndim != 1) return false;
        if (self.strides) |s| {
            return s[0] == @as(isize, @intCast(self.itemsize));
        }
        return true;
    }

    pub fn totalBytes(self: *const Self) usize {
        return self.len * self.itemsize;
    }
};

// ============================================================================
// Pointer Handling
// ============================================================================

/// Validate a pointer
pub fn validatePointer(ptr: ?*anyopaque, expected_align: usize) !*anyopaque {
    if (ptr == null) {
        return error.NullPointer;
    }

    const addr = @intFromPtr(ptr);
    if (addr % expected_align != 0) {
        return error.MisalignedPointer;
    }

    return ptr.?;
}

/// Calculate pointer offset
pub fn pointerOffset(comptime T: type, ptr: [*]T, offset: isize) [*]T {
    if (offset >= 0) {
        return ptr + @as(usize, @intCast(offset));
    } else {
        return ptr - @as(usize, @intCast(-offset));
    }
}

// ============================================================================
// Test Cases
// ============================================================================

fn testCTypesAllocator() !void {
    var alloc = CTypesAllocator.init(std.testing.allocator);

    const mem1 = try alloc.alloc(100);
    const mem2 = try alloc.alloc(200);

    const stats = alloc.stats();
    try std.testing.expectEqual(@as(usize, 300), stats.total_allocated);
    try std.testing.expectEqual(@as(usize, 2), stats.allocation_count);

    alloc.free(mem1);
    alloc.free(mem2);

    try std.testing.expectEqual(@as(usize, 2), alloc.stats().deallocation_count);
}

fn testTypeRegistry() !void {
    var registry = TypeRegistry.init();

    const int_id = try registry.register("c_int", 4, 4);
    const double_id = try registry.register("c_double", 8, 8);

    try std.testing.expectEqual(@as(u32, 0), int_id);
    try std.testing.expectEqual(@as(u32, 1), double_id);

    const int_entry = registry.lookup(int_id);
    try std.testing.expect(int_entry != null);
    try std.testing.expectEqual(@as(usize, 4), int_entry.?.size);

    const by_name = registry.lookupByName("c_double");
    try std.testing.expect(by_name != null);
    try std.testing.expectEqual(@as(usize, 8), by_name.?.size);
}

fn testObjectHeader() !void {
    var header = ObjectHeader.init(42);

    try std.testing.expectEqual(@as(u32, 1), header.ref_count);

    header.incRef();
    try std.testing.expectEqual(@as(u32, 2), header.ref_count);

    const should_free = header.decRef();
    try std.testing.expect(!should_free);
    try std.testing.expectEqual(@as(u32, 1), header.ref_count);

    const should_free2 = header.decRef();
    try std.testing.expect(should_free2);
}

fn testObjectFlags() !void {
    var flags = ObjectFlags{};

    try std.testing.expect(!flags.is_pointer);
    try std.testing.expect(flags.owns_memory);

    flags.is_pointer = true;
    flags.is_readonly = true;

    try std.testing.expect(flags.is_pointer);
    try std.testing.expect(flags.is_readonly);
}

fn testBufferInfo() !void {
    var data: [100]u8 = undefined;
    var info = BufferInfo{
        .ptr = @ptrCast(&data),
        .len = 100,
        .itemsize = 1,
    };

    try std.testing.expect(info.isContiguous());
    try std.testing.expectEqual(@as(usize, 100), info.totalBytes());
}

fn testBufferInfoNonContiguous() !void {
    var strides = [_]isize{2}; // Stride of 2 for itemsize 1 = non-contiguous
    var info = BufferInfo{
        .len = 50,
        .itemsize = 1,
        .strides = &strides,
    };

    try std.testing.expect(!info.isContiguous());
}

fn testValidatePointer() !void {
    var value: i32 align(4) = 42;
    const ptr = try validatePointer(@ptrCast(&value), 4);
    try std.testing.expect(ptr != null);
}

fn testValidateNullPointer() !void {
    try std.testing.expectError(error.NullPointer, validatePointer(null, 4));
}

fn testPointerOffset() !void {
    var arr = [_]i32{ 0, 10, 20, 30, 40 };
    const base: [*]i32 = &arr;

    const ptr1 = pointerOffset(i32, base, 2);
    try std.testing.expectEqual(@as(i32, 20), ptr1[0]);

    const ptr2 = pointerOffset(i32, base + 4, -2);
    try std.testing.expectEqual(@as(i32, 20), ptr2[0]);
}

fn testTypeRegistryFull() !void {
    var registry = TypeRegistry.init();

    // Fill the registry
    for (0..64) |i| {
        var buf: [32]u8 = undefined;
        const name = std.fmt.bufPrint(&buf, "type_{d}", .{i}) catch "type";
        _ = try registry.register(name, 4, 4);
    }

    // Should fail on 65th
    var buf: [32]u8 = undefined;
    const name = std.fmt.bufPrint(&buf, "type_64", .{}) catch "type";
    try std.testing.expectError(error.RegistryFull, registry.register(name, 4, 4));
}

fn testRegistryLookupMissing() !void {
    const registry = TypeRegistry.init();
    try std.testing.expect(registry.lookup(999) == null);
    try std.testing.expect(registry.lookupByName("nonexistent") == null);
}

// ============================================================================
// Zig Test Declarations
// ============================================================================

test "ctypes_allocator" {
    try testCTypesAllocator();
}

test "type_registry" {
    try testTypeRegistry();
}

test "object_header" {
    try testObjectHeader();
}

test "object_flags" {
    try testObjectFlags();
}

test "buffer_info" {
    try testBufferInfo();
}

test "buffer_info_non_contiguous" {
    try testBufferInfoNonContiguous();
}

test "validate_pointer" {
    try testValidatePointer();
}

test "validate_null_pointer" {
    try testValidateNullPointer();
}

test "pointer_offset" {
    try testPointerOffset();
}

test "type_registry_full" {
    try testTypeRegistryFull();
}

test "registry_lookup_missing" {
    try testRegistryLookupMissing();
}
