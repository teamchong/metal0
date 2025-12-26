/// Bytecode Opcodes - Stable metal0 bytecode instruction set
///
/// This is the canonical opcode definition for metal0's bytecode VM.
/// These opcodes are stable and versioned - they do NOT change with CPython versions.
///
/// The VM dispatches to existing runtime functions (unified_int_ops, equality, etc.)
/// rather than reimplementing Python semantics.
///
/// Freeze classification:
/// - FREEZABLE: Can be compiled to native Zig code
/// - VM_ONLY: Must run in bytecode VM (dynamic features)
const std = @import("std");

/// Bytecode format version (increment on breaking changes)
pub const BYTECODE_VERSION: u32 = 1;

/// Magic bytes for bytecode files: "M0BC" (Metal0 ByteCode)
pub const BYTECODE_MAGIC: [4]u8 = .{ 'M', '0', 'B', 'C' };

/// Opcode categories for organization and freeze classification
pub const OpcodeCategory = enum {
    stack,      // Stack manipulation (0x00-0x0F)
    constant,   // Constant loading (0x10-0x1F)
    local,      // Local variable access (0x20-0x2F)
    name,       // Name/global access (0x30-0x3F)
    binary,     // Binary operators (0x40-0x4F)
    unary,      // Unary operators (0x50-0x5F)
    compare,    // Comparison operators (0x60-0x6F)
    control,    // Control flow (0x70-0x7F)
    call,       // Function calls (0x80-0x8F)
    build,      // Build containers (0x90-0x9F)
    attr,       // Attribute access (0xA0-0xAF)
    subscr,     // Subscript access (0xB0-0xBF)
    exception,  // Exception handling (0xC0-0xCF)
    closure,    // Closure operations (0xD0-0xDF)
    generator,  // Generator/async (0xE0-0xEF)
    import,     // Import operations (0xF0-0xFF)
};

/// Freeze classification - can this opcode be compiled to native code?
pub const FreezeClass = enum {
    freezable,      // Can be compiled to Zig
    partial,        // Freezable with constraints
    vm_only,        // Must run in VM
};

/// Metal0 bytecode opcodes
///
/// Encoding:
/// - Single byte opcode
/// - Variable-length argument (0-4 bytes, varint encoding)
pub const Opcode = enum(u8) {
    // ========================================
    // Stack operations (0x00-0x0F) - FREEZABLE
    // ========================================
    NOP = 0x00,         // No operation
    POP = 0x01,         // Pop TOS
    DUP = 0x02,         // Duplicate TOS
    DUP2 = 0x03,        // Duplicate top 2 items
    ROT2 = 0x04,        // Swap top 2 items
    ROT3 = 0x05,        // Rotate top 3 items
    ROT4 = 0x06,        // Rotate top 4 items

    // ========================================
    // Constants (0x10-0x1F) - FREEZABLE
    // ========================================
    LOAD_CONST = 0x10,  // Push constant[arg] to stack
    LOAD_NONE = 0x11,   // Push None
    LOAD_TRUE = 0x12,   // Push True
    LOAD_FALSE = 0x13,  // Push False
    LOAD_I8 = 0x14,     // Push signed 8-bit int (arg is value)
    LOAD_I16 = 0x15,    // Push signed 16-bit int
    LOAD_I32 = 0x16,    // Push signed 32-bit int
    LOAD_ZERO = 0x17,   // Push 0
    LOAD_ONE = 0x18,    // Push 1

    // ========================================
    // Local variables (0x20-0x2F) - FREEZABLE
    // ========================================
    LOAD_FAST = 0x20,   // Push locals[arg]
    STORE_FAST = 0x21,  // Pop to locals[arg]
    DELETE_FAST = 0x22, // Delete locals[arg]
    LOAD_FAST_0 = 0x23, // Push locals[0] (optimized)
    LOAD_FAST_1 = 0x24, // Push locals[1]
    LOAD_FAST_2 = 0x25, // Push locals[2]
    LOAD_FAST_3 = 0x26, // Push locals[3]
    STORE_FAST_0 = 0x27, // Pop to locals[0]
    STORE_FAST_1 = 0x28, // Pop to locals[1]
    STORE_FAST_2 = 0x29, // Pop to locals[2]
    STORE_FAST_3 = 0x2A, // Pop to locals[3]

    // ========================================
    // Names/globals (0x30-0x3F) - VM_ONLY
    // ========================================
    LOAD_NAME = 0x30,   // Push value of name[arg]
    STORE_NAME = 0x31,  // Pop to name[arg]
    DELETE_NAME = 0x32, // Delete name[arg]
    LOAD_GLOBAL = 0x33, // Push global[arg]
    STORE_GLOBAL = 0x34, // Pop to global[arg]
    DELETE_GLOBAL = 0x35, // Delete global[arg]

    // ========================================
    // Binary operators (0x40-0x4F) - FREEZABLE
    // ========================================
    ADD = 0x40,         // TOS = TOS1 + TOS
    SUB = 0x41,         // TOS = TOS1 - TOS
    MUL = 0x42,         // TOS = TOS1 * TOS
    DIV = 0x43,         // TOS = TOS1 / TOS (true division, float result)
    FLOORDIV = 0x44,    // TOS = TOS1 // TOS
    MOD = 0x45,         // TOS = TOS1 % TOS (Python semantics)
    POW = 0x46,         // TOS = TOS1 ** TOS
    MATMUL = 0x47,      // TOS = TOS1 @ TOS
    LSHIFT = 0x48,      // TOS = TOS1 << TOS
    RSHIFT = 0x49,      // TOS = TOS1 >> TOS
    AND = 0x4A,         // TOS = TOS1 & TOS (bitwise)
    OR = 0x4B,          // TOS = TOS1 | TOS (bitwise)
    XOR = 0x4C,         // TOS = TOS1 ^ TOS (bitwise)

    // ========================================
    // Unary operators (0x50-0x5F) - FREEZABLE
    // ========================================
    NEG = 0x50,         // TOS = -TOS
    POS = 0x51,         // TOS = +TOS (type check)
    NOT = 0x52,         // TOS = not TOS (boolean)
    INVERT = 0x53,      // TOS = ~TOS (bitwise)

    // ========================================
    // Comparison (0x60-0x6F) - FREEZABLE
    // ========================================
    LT = 0x60,          // TOS = TOS1 < TOS
    LE = 0x61,          // TOS = TOS1 <= TOS
    EQ = 0x62,          // TOS = TOS1 == TOS
    NE = 0x63,          // TOS = TOS1 != TOS
    GT = 0x64,          // TOS = TOS1 > TOS
    GE = 0x65,          // TOS = TOS1 >= TOS
    IS = 0x66,          // TOS = TOS1 is TOS
    IS_NOT = 0x67,      // TOS = TOS1 is not TOS
    IN = 0x68,          // TOS = TOS1 in TOS
    NOT_IN = 0x69,      // TOS = TOS1 not in TOS

    // ========================================
    // Control flow (0x70-0x7F) - FREEZABLE
    // ========================================
    JUMP = 0x70,        // Unconditional jump to arg
    JUMP_IF_TRUE = 0x71, // Jump if TOS is true (pop)
    JUMP_IF_FALSE = 0x72, // Jump if TOS is false (pop)
    JUMP_IF_TRUE_OR_POP = 0x73, // Jump if true, else pop
    JUMP_IF_FALSE_OR_POP = 0x74, // Jump if false, else pop
    FOR_ITER = 0x75,    // Get next from iterator or jump
    GET_ITER = 0x76,    // TOS = iter(TOS)
    GET_LEN = 0x77,     // TOS = len(TOS)

    // ========================================
    // Function calls (0x80-0x8F) - PARTIAL
    // ========================================
    CALL = 0x80,        // Call function: argc in arg
    CALL_0 = 0x81,      // Call with 0 args
    CALL_1 = 0x82,      // Call with 1 arg
    CALL_2 = 0x83,      // Call with 2 args
    CALL_3 = 0x84,      // Call with 3 args
    CALL_KW = 0x85,     // Call with keyword args (VM only)
    CALL_VAR = 0x86,    // Call with *args (VM only)
    CALL_VAR_KW = 0x87, // Call with *args, **kwargs (VM only)
    RETURN = 0x88,      // Return TOS
    RETURN_NONE = 0x89, // Return None

    // ========================================
    // Build containers (0x90-0x9F) - FREEZABLE
    // ========================================
    BUILD_LIST = 0x90,  // Build list from arg items
    BUILD_TUPLE = 0x91, // Build tuple from arg items
    BUILD_SET = 0x92,   // Build set from arg items
    BUILD_DICT = 0x93,  // Build dict from arg key/value pairs
    BUILD_SLICE = 0x94, // Build slice (2 or 3 args)
    LIST_APPEND = 0x95, // Append TOS to list at TOS1[arg]
    SET_ADD = 0x96,     // Add TOS to set at TOS1[arg]
    DICT_UPDATE = 0x97, // Update dict at TOS1[arg] with TOS

    // ========================================
    // Attribute access (0xA0-0xAF) - PARTIAL
    // ========================================
    LOAD_ATTR = 0xA0,   // TOS = TOS.name[arg]
    STORE_ATTR = 0xA1,  // TOS1.name[arg] = TOS
    DELETE_ATTR = 0xA2, // del TOS.name[arg]
    LOAD_METHOD = 0xA3, // Optimized method lookup

    // ========================================
    // Subscript access (0xB0-0xBF) - PARTIAL
    // ========================================
    BINARY_SUBSCR = 0xB0, // TOS = TOS1[TOS]
    STORE_SUBSCR = 0xB1,  // TOS2[TOS1] = TOS
    DELETE_SUBSCR = 0xB2, // del TOS1[TOS]

    // ========================================
    // Exception handling (0xC0-0xCF) - VM_ONLY
    // ========================================
    PUSH_EXC_INFO = 0xC0,  // Push exception handler
    POP_EXC_INFO = 0xC1,   // Pop exception handler
    RAISE = 0xC2,          // Raise exception
    RERAISE = 0xC3,        // Re-raise current exception
    CHECK_EXC_MATCH = 0xC4, // Check if exception matches
    SETUP_FINALLY = 0xC5,  // Setup finally block

    // ========================================
    // Closures (0xD0-0xDF) - VM_ONLY
    // ========================================
    LOAD_DEREF = 0xD0,   // Load from cell[arg]
    STORE_DEREF = 0xD1,  // Store to cell[arg]
    DELETE_DEREF = 0xD2, // Delete cell[arg]
    LOAD_CLOSURE = 0xD3, // Push cell[arg] object
    MAKE_FUNCTION = 0xD4, // Create function object
    MAKE_CELL = 0xD5,    // Create cell for local

    // ========================================
    // Generators/async (0xE0-0xEF) - VM_ONLY
    // ========================================
    YIELD_VALUE = 0xE0,  // Yield TOS
    YIELD_FROM = 0xE1,   // Yield from iterator
    AWAIT = 0xE2,        // Await coroutine
    SEND = 0xE3,         // Send to generator

    // ========================================
    // Import (0xF0-0xFF) - VM_ONLY
    // ========================================
    IMPORT_NAME = 0xF0,  // Import module name[arg]
    IMPORT_FROM = 0xF1,  // Import attribute name[arg] from TOS
    IMPORT_STAR = 0xF2,  // Import * from TOS

    /// Get the category for this opcode
    pub fn category(self: Opcode) OpcodeCategory {
        const byte = @intFromEnum(self);
        return switch (byte >> 4) {
            0x0 => .stack,
            0x1 => .constant,
            0x2 => .local,
            0x3 => .name,
            0x4 => .binary,
            0x5 => .unary,
            0x6 => .compare,
            0x7 => .control,
            0x8 => .call,
            0x9 => .build,
            0xA => .attr,
            0xB => .subscr,
            0xC => .exception,
            0xD => .closure,
            0xE => .generator,
            0xF => .import,
            else => unreachable,
        };
    }

    /// Get the freeze classification for this opcode
    pub fn freezeClass(self: Opcode) FreezeClass {
        return switch (self.category()) {
            .stack, .constant, .local, .binary, .unary, .compare, .control, .build => .freezable,
            .call, .attr, .subscr => .partial,
            .name, .exception, .closure, .generator, .import => .vm_only,
        };
    }

    /// Check if this opcode has an argument
    pub fn hasArg(self: Opcode) bool {
        return switch (self) {
            // No-arg opcodes
            .NOP, .POP, .DUP, .DUP2, .ROT2, .ROT3, .ROT4,
            .LOAD_NONE, .LOAD_TRUE, .LOAD_FALSE, .LOAD_ZERO, .LOAD_ONE,
            .LOAD_FAST_0, .LOAD_FAST_1, .LOAD_FAST_2, .LOAD_FAST_3,
            .STORE_FAST_0, .STORE_FAST_1, .STORE_FAST_2, .STORE_FAST_3,
            .ADD, .SUB, .MUL, .DIV, .FLOORDIV, .MOD, .POW, .MATMUL,
            .LSHIFT, .RSHIFT, .AND, .OR, .XOR,
            .NEG, .POS, .NOT, .INVERT,
            .LT, .LE, .EQ, .NE, .GT, .GE, .IS, .IS_NOT, .IN, .NOT_IN,
            .GET_ITER, .GET_LEN,
            .CALL_0, .CALL_1, .CALL_2, .CALL_3,
            .RETURN, .RETURN_NONE,
            .BINARY_SUBSCR, .STORE_SUBSCR, .DELETE_SUBSCR,
            .POP_EXC_INFO, .RAISE, .RERAISE, .CHECK_EXC_MATCH,
            .YIELD_VALUE, .YIELD_FROM, .AWAIT, .SEND,
            .IMPORT_STAR,
            => false,
            else => true,
        };
    }

    /// Get human-readable name
    pub fn name(self: Opcode) []const u8 {
        return @tagName(self);
    }
};

/// Instruction with decoded argument
pub const Instruction = struct {
    op: Opcode,
    arg: u32 = 0,

    /// Size of this instruction in bytes
    pub fn size(self: Instruction) usize {
        if (!self.op.hasArg()) return 1;
        return 1 + varIntSize(self.arg);
    }
};

/// Calculate varint encoding size
fn varIntSize(value: u32) usize {
    if (value < 0x80) return 1;
    if (value < 0x4000) return 2;
    if (value < 0x200000) return 3;
    if (value < 0x10000000) return 4;
    return 5;
}

/// Encode a varint to buffer, return bytes written
pub fn encodeVarInt(value: u32, buf: []u8) usize {
    var v = value;
    var i: usize = 0;
    while (v >= 0x80) : (i += 1) {
        buf[i] = @intCast((v & 0x7F) | 0x80);
        v >>= 7;
    }
    buf[i] = @intCast(v);
    return i + 1;
}

/// Decode a varint from buffer, return value and bytes consumed
pub fn decodeVarInt(buf: []const u8) struct { value: u32, size: usize } {
    var result: u32 = 0;
    var shift: u5 = 0;
    var i: usize = 0;
    while (i < buf.len and i < 5) : (i += 1) {
        const byte = buf[i];
        result |= @as(u32, byte & 0x7F) << shift;
        if (byte & 0x80 == 0) {
            return .{ .value = result, .size = i + 1 };
        }
        shift += 7;
    }
    return .{ .value = result, .size = i };
}

test "opcode categories" {
    const testing = std.testing;

    try testing.expectEqual(OpcodeCategory.stack, Opcode.NOP.category());
    try testing.expectEqual(OpcodeCategory.constant, Opcode.LOAD_CONST.category());
    try testing.expectEqual(OpcodeCategory.binary, Opcode.ADD.category());
    try testing.expectEqual(OpcodeCategory.compare, Opcode.LT.category());
    try testing.expectEqual(OpcodeCategory.import, Opcode.IMPORT_NAME.category());
}

test "freeze classification" {
    const testing = std.testing;

    try testing.expectEqual(FreezeClass.freezable, Opcode.ADD.freezeClass());
    try testing.expectEqual(FreezeClass.partial, Opcode.CALL.freezeClass());
    try testing.expectEqual(FreezeClass.vm_only, Opcode.IMPORT_NAME.freezeClass());
}

test "varint encoding" {
    const testing = std.testing;
    var buf: [5]u8 = undefined;

    // Small value
    try testing.expectEqual(@as(usize, 1), encodeVarInt(42, &buf));
    try testing.expectEqual(@as(u8, 42), buf[0]);

    // Larger value
    try testing.expectEqual(@as(usize, 2), encodeVarInt(300, &buf));
    const decoded = decodeVarInt(&buf);
    try testing.expectEqual(@as(u32, 300), decoded.value);
    try testing.expectEqual(@as(usize, 2), decoded.size);
}
