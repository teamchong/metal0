/// _opcode_metadata/types.zig - Core type definitions
/// Defines the fundamental types for opcode metadata, including categories,
/// flags, stack effects, and opcode definitions.

const std = @import("std");

/// Opcode categories
pub const OpcodeCategory = enum {
    pseudo, // Pseudo instructions (not real opcodes)
    specialized, // Specialized/optimized versions
    cache, // Cache entries
    general, // General instructions
    jump, // Jump instructions
    load, // Load operations
    store, // Store operations
    call, // Call operations
    binary, // Binary operations
    unary, // Unary operations
    compare, // Comparison operations
    import_op, // Import operations
    exception, // Exception handling
    generator, // Generator operations
    coroutine, // Coroutine operations
    intrinsic, // Intrinsic operations
};

/// Opcode flags
pub const OpcodeFlags = packed struct {
    has_arg: bool = false, // Has an argument
    has_const: bool = false, // Argument is a constant index
    has_name: bool = false, // Argument is a name index
    has_local: bool = false, // Argument is a local variable index
    has_free: bool = false, // Argument is a free variable index
    has_jump: bool = false, // Has a jump target
    has_cache: bool = false, // Has cache entries
    is_pseudo: bool = false, // Is a pseudo instruction
};

/// Stack effect of an instruction
pub const StackEffect = struct {
    /// Number of items popped
    pop: i8 = 0,
    /// Number of items pushed
    push: i8 = 0,
    /// Whether effect varies with argument
    varies: bool = false,

    /// Net stack effect
    pub fn net(self: StackEffect) i8 {
        return self.push - self.pop;
    }
};

/// Complete opcode definition
pub const OpcodeDef = struct {
    /// Opcode value (0-255)
    code: u8,
    /// Mnemonic name
    name: []const u8,
    /// Category
    category: OpcodeCategory = .general,
    /// Flags
    flags: OpcodeFlags = .{},
    /// Stack effect
    stack_effect: StackEffect = .{},
    /// Number of cache entries
    cache_entries: u8 = 0,
    /// Base opcode (for specialized)
    base_opcode: ?u8 = null,
};

test "stack effect calculation" {
    const effect = StackEffect{ .pop = 2, .push = 1 };
    try std.testing.expectEqual(@as(i8, -1), effect.net());
}

test "opcode flags default" {
    const flags = OpcodeFlags{};
    try std.testing.expect(!flags.has_arg);
    try std.testing.expect(!flags.has_cache);
}
