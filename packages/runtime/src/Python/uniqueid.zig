/// uniqueid - Unique ID Generation
/// Mirrors cpython/Python/uniqueid.c
///
/// Generates unique identifiers for various Python runtime objects.
/// Used for code objects, heap types, and other internal tracking.

const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;

// ============================================================================
// ID Types
// ============================================================================

/// Unique ID type (64-bit)
pub const UniqueId = u64;

/// Special ID values
pub const INVALID_ID: UniqueId = 0;
pub const RESERVED_START: UniqueId = 1;
pub const RESERVED_END: UniqueId = 1000;

/// ID namespace
pub const IdNamespace = enum(u8) {
    /// Code objects
    code = 0,
    /// Frame objects
    frame = 1,
    /// Type objects
    type_obj = 2,
    /// Function objects
    function = 3,
    /// Module objects
    module = 4,
    /// Generator objects
    generator = 5,
    /// Coroutine objects
    coroutine = 6,
    /// Async generator objects
    async_generator = 7,
    /// Thread state
    thread = 8,
    /// Interpreter state
    interpreter = 9,
    /// General purpose
    general = 255,
};

// ============================================================================
// ID Generator
// ============================================================================

/// Unique ID generator
pub const IdGenerator = struct {
    const Self = @This();

    /// Next ID per namespace
    counters: [256]std.atomic.Value(u64),
    /// Process ID component
    process_id: u32,
    /// Start timestamp
    start_time: i64,
    /// Is thread-safe
    thread_safe: bool,

    pub fn init() Self {
        var gen = Self{
            .counters = undefined,
            .process_id = getProcessId(),
            .start_time = std.time.timestamp(),
            .thread_safe = true,
        };

        // Initialize all counters to reserved end
        for (&gen.counters) |*counter| {
            counter.* = std.atomic.Value(u64).init(RESERVED_END);
        }

        return gen;
    }

    /// Generate next ID for namespace
    pub fn nextId(self: *Self, namespace: IdNamespace) UniqueId {
        const ns_idx = @intFromEnum(namespace);
        const seq = self.counters[ns_idx].fetchAdd(1, .monotonic);

        // Combine: namespace (8 bits) | process (16 bits) | sequence (40 bits)
        const ns_part: u64 = @as(u64, ns_idx) << 56;
        const proc_part: u64 = @as(u64, self.process_id & 0xFFFF) << 40;
        const seq_part: u64 = seq & 0xFFFFFFFFFF;

        return ns_part | proc_part | seq_part;
    }

    /// Generate next ID (general namespace)
    pub fn next(self: *Self) UniqueId {
        return self.nextId(.general);
    }

    /// Parse ID components
    pub fn parseId(id: UniqueId) struct {
        namespace: IdNamespace,
        process: u16,
        sequence: u64,
    } {
        return .{
            .namespace = @enumFromInt(@as(u8, @truncate(id >> 56))),
            .process = @truncate((id >> 40) & 0xFFFF),
            .sequence = id & 0xFFFFFFFFFF,
        };
    }

    /// Check if ID is valid
    pub fn isValid(id: UniqueId) bool {
        return id > RESERVED_END;
    }

    /// Get current sequence for namespace
    pub fn getCurrentSequence(self: *const Self, namespace: IdNamespace) u64 {
        const ns_idx = @intFromEnum(namespace);
        return self.counters[ns_idx].load(.monotonic);
    }
};

// ============================================================================
// Code Object ID
// ============================================================================

/// Code object unique ID tracker
pub const CodeObjectId = struct {
    const Self = @This();

    /// ID generator
    generator: *IdGenerator,
    /// ID to code object mapping
    id_map: std.AutoHashMap(UniqueId, *anyopaque),
    /// Allocator
    allocator: Allocator,

    pub fn init(allocator: Allocator, generator: *IdGenerator) Self {
        return Self{
            .allocator = allocator,
            .generator = generator,
            .id_map = std.AutoHashMap(UniqueId, *anyopaque).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.id_map.deinit();
    }

    /// Assign ID to code object
    pub fn assignId(self: *Self, code: *anyopaque) !UniqueId {
        const id = self.generator.nextId(.code);
        try self.id_map.put(id, code);
        return id;
    }

    /// Get code object by ID
    pub fn getCode(self: *const Self, id: UniqueId) ?*anyopaque {
        return self.id_map.get(id);
    }

    /// Remove code object
    pub fn removeId(self: *Self, id: UniqueId) void {
        _ = self.id_map.remove(id);
    }

    /// Get count
    pub fn count(self: *const Self) usize {
        return self.id_map.count();
    }
};

// ============================================================================
// Heap Type ID
// ============================================================================

/// Heap type unique ID tracker
pub const HeapTypeId = struct {
    const Self = @This();

    /// ID generator
    generator: *IdGenerator,
    /// Type name to ID mapping
    name_to_id: std.StringHashMap(UniqueId),
    /// ID to type mapping
    id_to_type: std.AutoHashMap(UniqueId, *anyopaque),
    /// Allocator
    allocator: Allocator,

    pub fn init(allocator: Allocator, generator: *IdGenerator) Self {
        return Self{
            .allocator = allocator,
            .generator = generator,
            .name_to_id = std.StringHashMap(UniqueId).init(allocator),
            .id_to_type = std.AutoHashMap(UniqueId, *anyopaque).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.name_to_id.deinit();
        self.id_to_type.deinit();
    }

    /// Register heap type
    pub fn registerType(self: *Self, type_obj: *anyopaque, name: []const u8) !UniqueId {
        // Check if already registered
        if (self.name_to_id.get(name)) |existing_id| {
            return existing_id;
        }

        const id = self.generator.nextId(.type_obj);
        const name_copy = try self.allocator.dupe(u8, name);
        try self.name_to_id.put(name_copy, id);
        try self.id_to_type.put(id, type_obj);
        return id;
    }

    /// Get type by name
    pub fn getTypeByName(self: *const Self, name: []const u8) ?*anyopaque {
        const id = self.name_to_id.get(name) orelse return null;
        return self.id_to_type.get(id);
    }

    /// Get type by ID
    pub fn getTypeById(self: *const Self, id: UniqueId) ?*anyopaque {
        return self.id_to_type.get(id);
    }
};

// ============================================================================
// UUID Generation
// ============================================================================

/// Generate UUID v4 (random)
pub fn generateUUID() [16]u8 {
    var uuid: [16]u8 = undefined;

    // Fill with random bytes
    std.crypto.random.bytes(&uuid);

    // Set version (4) and variant (RFC 4122)
    uuid[6] = (uuid[6] & 0x0F) | 0x40; // Version 4
    uuid[8] = (uuid[8] & 0x3F) | 0x80; // Variant 1

    return uuid;
}

/// Format UUID as string
pub fn formatUUID(uuid: [16]u8) [36]u8 {
    var result: [36]u8 = undefined;
    const hex = "0123456789abcdef";

    var out_idx: usize = 0;
    for (uuid, 0..) |byte, i| {
        if (i == 4 or i == 6 or i == 8 or i == 10) {
            result[out_idx] = '-';
            out_idx += 1;
        }
        result[out_idx] = hex[byte >> 4];
        result[out_idx + 1] = hex[byte & 0x0F];
        out_idx += 2;
    }

    return result;
}

/// Parse UUID from string
pub fn parseUUID(str: []const u8) ?[16]u8 {
    if (str.len != 36) return null;

    var uuid: [16]u8 = undefined;
    var byte_idx: usize = 0;

    var i: usize = 0;
    while (i < str.len) : (i += 1) {
        if (str[i] == '-') continue;

        if (i + 1 >= str.len) return null;

        const high = hexDigit(str[i]) orelse return null;
        const low = hexDigit(str[i + 1]) orelse return null;
        uuid[byte_idx] = (high << 4) | low;
        byte_idx += 1;
        i += 1;
    }

    if (byte_idx != 16) return null;
    return uuid;
}

fn hexDigit(c: u8) ?u4 {
    return switch (c) {
        '0'...'9' => @intCast(c - '0'),
        'a'...'f' => @intCast(c - 'a' + 10),
        'A'...'F' => @intCast(c - 'A' + 10),
        else => null,
    };
}

// ============================================================================
// Process/Thread ID Helpers
// ============================================================================

/// Get current process ID
fn getProcessId() u32 {
    if (builtin.os.tag == .linux) {
        return @intCast(std.os.linux.getpid());
    } else if (builtin.os.tag == .macos or builtin.os.tag == .freebsd) {
        return @intCast(std.c.getpid());
    }
    return 0;
}

/// Get current thread ID (platform specific)
pub fn getThreadId() u64 {
    if (builtin.os.tag == .linux) {
        return @intCast(std.os.linux.gettid());
    }
    // Fallback: use address of thread-local variable
    const S = struct {
        threadlocal var marker: u8 = 0;
    };
    return @intFromPtr(&S.marker);
}

// ============================================================================
// Module State
// ============================================================================

var initialized: bool = false;
var global_generator: ?IdGenerator = null;

/// Initialize the uniqueid module
pub fn init() void {
    if (initialized) return;
    global_generator = IdGenerator.init();
    initialized = true;
}

/// Get global ID generator
pub fn getGenerator() *IdGenerator {
    if (global_generator == null) {
        global_generator = IdGenerator.init();
    }
    return &global_generator.?;
}

/// Generate next unique ID
pub fn nextUniqueId() UniqueId {
    return getGenerator().next();
}

/// Generate next ID for namespace
pub fn nextIdForNamespace(namespace: IdNamespace) UniqueId {
    return getGenerator().nextId(namespace);
}

/// Reset module state
pub fn reset() void {
    global_generator = null;
    initialized = false;
}

// ============================================================================
// Tests
// ============================================================================

test "id generator basic" {
    var gen = IdGenerator.init();

    const id1 = gen.next();
    const id2 = gen.next();

    try std.testing.expect(IdGenerator.isValid(id1));
    try std.testing.expect(IdGenerator.isValid(id2));
    try std.testing.expect(id1 != id2);
}

test "id generator namespaces" {
    var gen = IdGenerator.init();

    const code_id = gen.nextId(.code);
    const frame_id = gen.nextId(.frame);

    const code_parsed = IdGenerator.parseId(code_id);
    const frame_parsed = IdGenerator.parseId(frame_id);

    try std.testing.expectEqual(IdNamespace.code, code_parsed.namespace);
    try std.testing.expectEqual(IdNamespace.frame, frame_parsed.namespace);
}

test "id parsing" {
    var gen = IdGenerator.init();
    const id = gen.nextId(.type_obj);

    const parsed = IdGenerator.parseId(id);
    try std.testing.expectEqual(IdNamespace.type_obj, parsed.namespace);
    try std.testing.expect(parsed.sequence > RESERVED_END);
}

test "uuid generation" {
    const uuid = generateUUID();

    // Check version (should be 4)
    try std.testing.expectEqual(@as(u8, 4), (uuid[6] >> 4));

    // Check variant (should be 1 - bits 10xx)
    try std.testing.expect((uuid[8] & 0xC0) == 0x80);
}

test "uuid formatting" {
    const uuid = [16]u8{ 0x12, 0x34, 0x56, 0x78, 0x9a, 0xbc, 0x4d, 0xef, 0x80, 0x12, 0x34, 0x56, 0x78, 0x9a, 0xbc, 0xde };
    const formatted = formatUUID(uuid);

    try std.testing.expectEqualStrings("12345678-9abc-4def-8012-3456789abcde", &formatted);
}

test "uuid parsing" {
    const uuid_str = "12345678-9abc-4def-8012-3456789abcde";
    const parsed = parseUUID(uuid_str);

    try std.testing.expect(parsed != null);
    try std.testing.expectEqual(@as(u8, 0x12), parsed.?[0]);
    try std.testing.expectEqual(@as(u8, 0xde), parsed.?[15]);
}

test "uuid roundtrip" {
    const original = generateUUID();
    const formatted = formatUUID(original);
    const parsed = parseUUID(&formatted);

    try std.testing.expect(parsed != null);
    try std.testing.expectEqualSlices(u8, &original, &parsed.?);
}

test "code object id tracker" {
    const allocator = std.testing.allocator;
    var gen = IdGenerator.init();
    var tracker = CodeObjectId.init(allocator, &gen);
    defer tracker.deinit();

    var dummy: u8 = 0;
    const id = try tracker.assignId(&dummy);

    try std.testing.expect(IdGenerator.isValid(id));
    try std.testing.expectEqual(@as(usize, 1), tracker.count());

    const retrieved = tracker.getCode(id);
    try std.testing.expect(retrieved != null);
}

test "invalid id" {
    try std.testing.expect(!IdGenerator.isValid(INVALID_ID));
    try std.testing.expect(!IdGenerator.isValid(RESERVED_START));
    try std.testing.expect(!IdGenerator.isValid(RESERVED_END));
}
