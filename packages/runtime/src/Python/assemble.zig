/// assemble - Bytecode Assembler
/// Mirrors cpython/Python/assemble.c
///
/// The assembler converts compiler-generated instructions into bytecode.
/// It handles jump target resolution, exception table generation, and
/// line number tables.

const std = @import("std");
const Allocator = std.mem.Allocator;

// ============================================================================
// Bytecode Constants
// ============================================================================

/// Maximum bytecode offset (24-bit)
pub const MAX_BYTECODE_OFFSET: u32 = 0xFFFFFF;

/// Extended arg threshold
pub const EXTENDED_ARG_THRESHOLD: u32 = 256;

/// Maximum instruction size (in bytes)
pub const MAX_INSTRUCTION_SIZE: usize = 10;

// ============================================================================
// Instruction Types
// ============================================================================

/// Raw instruction before assembly
pub const Instruction = struct {
    /// Opcode
    opcode: u8,
    /// Operand (may require EXTENDED_ARG)
    arg: u32 = 0,
    /// Source line number
    lineno: i32 = 0,
    /// Column offset
    col_offset: i32 = 0,
    /// End line number
    end_lineno: i32 = 0,
    /// End column offset
    end_col_offset: i32 = 0,
    /// Jump target (for branch instructions)
    target: ?*BasicBlock = null,
    /// Exception handler block
    except_handler: ?*BasicBlock = null,

    /// Check if instruction is a jump
    pub fn isJump(self: *const Instruction) bool {
        return self.target != null;
    }

    /// Check if instruction is unconditional jump
    pub fn isUnconditionalJump(self: *const Instruction) bool {
        return self.opcode == JUMP_ABSOLUTE or self.opcode == JUMP_FORWARD;
    }

    /// Get instruction size in bytes
    pub fn size(self: *const Instruction) usize {
        if (self.arg < EXTENDED_ARG_THRESHOLD) {
            return 2;
        } else if (self.arg < 0x10000) {
            return 4;
        } else if (self.arg < 0x1000000) {
            return 6;
        } else {
            return 8;
        }
    }
};

// Common opcodes (subset)
pub const NOP: u8 = 9;
pub const LOAD_CONST: u8 = 100;
pub const RETURN_VALUE: u8 = 83;
pub const JUMP_FORWARD: u8 = 110;
pub const JUMP_ABSOLUTE: u8 = 113;
pub const POP_JUMP_IF_TRUE: u8 = 115;
pub const POP_JUMP_IF_FALSE: u8 = 114;
pub const EXTENDED_ARG: u8 = 144;

// ============================================================================
// Basic Block
// ============================================================================

/// Basic block in control flow graph
pub const BasicBlock = struct {
    const Self = @This();

    /// Instructions in this block
    instructions: std.ArrayList(Instruction),
    /// Block offset in bytecode (set during assembly)
    offset: u32 = 0,
    /// Block has been visited during traversal
    visited: bool = false,
    /// Block is reachable
    reachable: bool = true,
    /// Next block in linear order
    next: ?*Self = null,
    /// True branch target (for conditional jumps)
    true_branch: ?*Self = null,
    /// False branch target / fallthrough
    false_branch: ?*Self = null,
    /// Exception handler for this block
    except_handler: ?*Self = null,
    /// Stack depth at block entry
    stack_depth: i32 = -1,
    /// Block ID for debugging
    id: u32 = 0,

    /// Create a new basic block
    pub fn init(allocator: Allocator, id: u32) Self {
        return Self{
            .instructions = std.ArrayList(Instruction).init(allocator),
            .id = id,
        };
    }

    /// Free block resources
    pub fn deinit(self: *Self) void {
        self.instructions.deinit();
    }

    /// Add instruction to block
    pub fn addInstruction(self: *Self, instr: Instruction) !void {
        try self.instructions.append(instr);
    }

    /// Get last instruction
    pub fn lastInstruction(self: *Self) ?*Instruction {
        if (self.instructions.items.len == 0) return null;
        return &self.instructions.items[self.instructions.items.len - 1];
    }

    /// Check if block ends with jump
    pub fn endsWithJump(self: *Self) bool {
        if (self.lastInstruction()) |instr| {
            return instr.isJump() or instr.isUnconditionalJump();
        }
        return false;
    }

    /// Calculate block size in bytes
    pub fn byteSize(self: *const Self) usize {
        var total: usize = 0;
        for (self.instructions.items) |instr| {
            total += instr.size();
        }
        return total;
    }
};

// ============================================================================
// Assembler State
// ============================================================================

/// Assembler state
pub const Assembler = struct {
    const Self = @This();

    /// Memory allocator
    allocator: Allocator,
    /// All basic blocks
    blocks: std.ArrayList(*BasicBlock),
    /// Entry block
    entry_block: ?*BasicBlock = null,
    /// Current block being built
    current_block: ?*BasicBlock = null,
    /// Output bytecode
    bytecode: std.ArrayList(u8),
    /// Line number table
    linetable: std.ArrayList(u8),
    /// Exception table
    exception_table: std.ArrayList(ExceptionEntry),
    /// Constants pool
    constants: std.ArrayList(Constant),
    /// Names pool
    names: std.ArrayList([]const u8),
    /// Block ID counter
    next_block_id: u32 = 0,
    /// Stack size
    stack_size: i32 = 0,
    /// Number of locals
    num_locals: u32 = 0,

    /// Create a new assembler
    pub fn init(allocator: Allocator) Self {
        return Self{
            .allocator = allocator,
            .blocks = std.ArrayList(*BasicBlock).init(allocator),
            .bytecode = std.ArrayList(u8).init(allocator),
            .linetable = std.ArrayList(u8).init(allocator),
            .exception_table = std.ArrayList(ExceptionEntry).init(allocator),
            .constants = std.ArrayList(Constant).init(allocator),
            .names = std.ArrayList([]const u8).init(allocator),
        };
    }

    /// Free assembler resources
    pub fn deinit(self: *Self) void {
        for (self.blocks.items) |block| {
            block.deinit();
            self.allocator.destroy(block);
        }
        self.blocks.deinit();
        self.bytecode.deinit();
        self.linetable.deinit();
        self.exception_table.deinit();
        self.constants.deinit();
        self.names.deinit();
    }

    /// Create a new basic block
    pub fn newBlock(self: *Self) !*BasicBlock {
        const block = try self.allocator.create(BasicBlock);
        block.* = BasicBlock.init(self.allocator, self.next_block_id);
        self.next_block_id += 1;
        try self.blocks.append(block);
        return block;
    }

    /// Set entry block
    pub fn setEntry(self: *Self, block: *BasicBlock) void {
        self.entry_block = block;
        self.current_block = block;
    }

    /// Switch to a different block
    pub fn useBlock(self: *Self, block: *BasicBlock) void {
        self.current_block = block;
    }

    /// Emit instruction to current block
    pub fn emit(self: *Self, opcode: u8, arg: u32) !void {
        if (self.current_block) |block| {
            try block.addInstruction(.{
                .opcode = opcode,
                .arg = arg,
            });
        }
    }

    /// Emit instruction with source location
    pub fn emitWithLocation(self: *Self, opcode: u8, arg: u32, lineno: i32, col_offset: i32) !void {
        if (self.current_block) |block| {
            try block.addInstruction(.{
                .opcode = opcode,
                .arg = arg,
                .lineno = lineno,
                .col_offset = col_offset,
            });
        }
    }

    /// Emit jump instruction
    pub fn emitJump(self: *Self, opcode: u8, target: *BasicBlock) !void {
        if (self.current_block) |block| {
            try block.addInstruction(.{
                .opcode = opcode,
                .target = target,
            });
        }
    }

    /// Add constant to pool, return index
    pub fn addConstant(self: *Self, constant: Constant) !u32 {
        // Check for existing constant
        for (self.constants.items, 0..) |c, i| {
            if (c.eql(constant)) {
                return @intCast(i);
            }
        }
        const index: u32 = @intCast(self.constants.items.len);
        try self.constants.append(constant);
        return index;
    }

    /// Add name to pool, return index
    pub fn addName(self: *Self, name: []const u8) !u32 {
        // Check for existing name
        for (self.names.items, 0..) |n, i| {
            if (std.mem.eql(u8, n, name)) {
                return @intCast(i);
            }
        }
        const index: u32 = @intCast(self.names.items.len);
        try self.names.append(name);
        return index;
    }

    /// Assemble all blocks into bytecode
    pub fn assemble(self: *Self) !AssembledCode {
        // Phase 1: Mark reachable blocks
        try self.markReachable();

        // Phase 2: Calculate block offsets
        try self.calculateOffsets();

        // Phase 3: Resolve jumps and emit bytecode
        try self.emitBytecode();

        // Phase 4: Generate line number table
        try self.generateLinetable();

        // Phase 5: Generate exception table
        try self.generateExceptionTable();

        return AssembledCode{
            .bytecode = try self.allocator.dupe(u8, self.bytecode.items),
            .linetable = try self.allocator.dupe(u8, self.linetable.items),
            .exception_table = try self.allocator.dupe(ExceptionEntry, self.exception_table.items),
            .constants = try self.allocator.dupe(Constant, self.constants.items),
            .names = try self.allocator.dupe([]const u8, self.names.items),
            .stack_size = self.stack_size,
            .num_locals = self.num_locals,
        };
    }

    /// Mark reachable blocks starting from entry
    fn markReachable(self: *Self) !void {
        if (self.entry_block == null) return;

        var worklist = std.ArrayList(*BasicBlock).init(self.allocator);
        defer worklist.deinit();

        // Reset visited flags
        for (self.blocks.items) |block| {
            block.visited = false;
            block.reachable = false;
        }

        try worklist.append(self.entry_block.?);
        self.entry_block.?.reachable = true;

        while (worklist.items.len > 0) {
            const block = worklist.pop();
            if (block.visited) continue;
            block.visited = true;

            // Add successors
            if (block.true_branch) |tb| {
                if (!tb.reachable) {
                    tb.reachable = true;
                    try worklist.append(tb);
                }
            }
            if (block.false_branch) |fb| {
                if (!fb.reachable) {
                    fb.reachable = true;
                    try worklist.append(fb);
                }
            }
            if (block.next) |next| {
                if (!next.reachable and !block.endsWithJump()) {
                    next.reachable = true;
                    try worklist.append(next);
                }
            }
        }
    }

    /// Calculate byte offsets for all blocks
    fn calculateOffsets(self: *Self) !void {
        var offset: u32 = 0;
        for (self.blocks.items) |block| {
            if (!block.reachable) continue;
            block.offset = offset;
            offset += @intCast(block.byteSize());
        }
    }

    /// Emit bytecode for all blocks
    fn emitBytecode(self: *Self) !void {
        for (self.blocks.items) |block| {
            if (!block.reachable) continue;

            for (block.instructions.items) |instr| {
                try self.emitInstruction(instr, block.offset);
            }
        }
    }

    /// Emit single instruction to bytecode
    fn emitInstruction(self: *Self, instr: Instruction, block_offset: u32) !void {
        var arg = instr.arg;

        // Resolve jump target
        if (instr.target) |target| {
            if (instr.opcode == JUMP_FORWARD) {
                // Relative jump
                arg = target.offset -| (block_offset + 2);
            } else {
                // Absolute jump
                arg = target.offset;
            }
        }

        // Emit EXTENDED_ARG if needed
        if (arg >= 0x1000000) {
            try self.bytecode.append(EXTENDED_ARG);
            try self.bytecode.append(@truncate(arg >> 24));
        }
        if (arg >= 0x10000) {
            try self.bytecode.append(EXTENDED_ARG);
            try self.bytecode.append(@truncate(arg >> 16));
        }
        if (arg >= EXTENDED_ARG_THRESHOLD) {
            try self.bytecode.append(EXTENDED_ARG);
            try self.bytecode.append(@truncate(arg >> 8));
        }

        // Emit opcode and arg
        try self.bytecode.append(instr.opcode);
        try self.bytecode.append(@truncate(arg));
    }

    /// Generate line number table (Python 3.11+ format)
    fn generateLinetable(self: *Self) !void {
        var prev_lineno: i32 = 0;

        for (self.blocks.items) |block| {
            if (!block.reachable) continue;

            for (block.instructions.items) |instr| {
                if (instr.lineno != prev_lineno and instr.lineno > 0) {
                    const delta = instr.lineno - prev_lineno;
                    try self.encodeLineDelta(delta);
                    prev_lineno = instr.lineno;
                }
            }
        }
    }

    /// Encode line number delta
    fn encodeLineDelta(self: *Self, delta: i32) !void {
        if (delta >= -128 and delta <= 127) {
            // Single byte encoding
            try self.linetable.append(@bitCast(@as(i8, @intCast(delta))));
        } else {
            // Extended encoding
            try self.linetable.append(0xFF);
            try self.linetable.append(@bitCast(@as(i8, @intCast(@divTrunc(delta, 256)))));
            try self.linetable.append(@truncate(@as(u32, @bitCast(delta))));
        }
    }

    /// Generate exception handler table
    fn generateExceptionTable(self: *Self) !void {
        for (self.blocks.items) |block| {
            if (!block.reachable) continue;
            if (block.except_handler) |handler| {
                try self.exception_table.append(.{
                    .start = block.offset,
                    .end = block.offset + @as(u32, @intCast(block.byteSize())),
                    .target = handler.offset,
                    .depth = @intCast(block.stack_depth),
                    .lasti = false,
                });
            }
        }
    }
};

// ============================================================================
// Output Types
// ============================================================================

/// Assembled bytecode output
pub const AssembledCode = struct {
    bytecode: []const u8,
    linetable: []const u8,
    exception_table: []const ExceptionEntry,
    constants: []const Constant,
    names: []const []const u8,
    stack_size: i32,
    num_locals: u32,
};

/// Exception table entry
pub const ExceptionEntry = struct {
    start: u32,
    end: u32,
    target: u32,
    depth: u16,
    lasti: bool,
};

/// Constant pool entry
pub const Constant = union(enum) {
    none: void,
    ellipsis: void,
    boolean: bool,
    integer: i64,
    float: f64,
    complex: struct { real: f64, imag: f64 },
    string: []const u8,
    bytes: []const u8,
    tuple: []const Constant,
    frozenset: []const Constant,
    code: *const anyopaque, // Code object reference

    pub fn eql(self: Constant, other: Constant) bool {
        return switch (self) {
            .none => other == .none,
            .ellipsis => other == .ellipsis,
            .boolean => |b| other == .boolean and other.boolean == b,
            .integer => |i| other == .integer and other.integer == i,
            .float => |f| other == .float and other.float == f,
            .string => |s| other == .string and std.mem.eql(u8, other.string, s),
            .bytes => |b| other == .bytes and std.mem.eql(u8, other.bytes, b),
            else => false,
        };
    }
};

// ============================================================================
// Utility Functions
// ============================================================================

/// Calculate stack effect of an opcode
pub fn stackEffect(opcode: u8, arg: u32, jump: bool) i32 {
    _ = arg;
    _ = jump;
    return switch (opcode) {
        NOP => 0,
        LOAD_CONST => 1,
        RETURN_VALUE => -1,
        else => 0,
    };
}

/// Check if opcode has argument
pub fn hasArg(opcode: u8) bool {
    return opcode >= 90; // HAVE_ARGUMENT threshold
}

/// Check if opcode is a jump
pub fn isJumpOpcode(opcode: u8) bool {
    return opcode == JUMP_FORWARD or
        opcode == JUMP_ABSOLUTE or
        opcode == POP_JUMP_IF_TRUE or
        opcode == POP_JUMP_IF_FALSE;
}

// ============================================================================
// Module Initialization
// ============================================================================

var initialized: bool = false;

/// Initialize the assembler module
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

test "basic block creation" {
    const allocator = std.testing.allocator;

    var assembler = Assembler.init(allocator);
    defer assembler.deinit();

    const block1 = try assembler.newBlock();
    const block2 = try assembler.newBlock();

    try std.testing.expectEqual(@as(u32, 0), block1.id);
    try std.testing.expectEqual(@as(u32, 1), block2.id);
}

test "instruction emission" {
    const allocator = std.testing.allocator;

    var assembler = Assembler.init(allocator);
    defer assembler.deinit();

    const block = try assembler.newBlock();
    assembler.setEntry(block);

    try assembler.emit(LOAD_CONST, 0);
    try assembler.emit(RETURN_VALUE, 0);

    try std.testing.expectEqual(@as(usize, 2), block.instructions.items.len);
}

test "constant deduplication" {
    const allocator = std.testing.allocator;

    var assembler = Assembler.init(allocator);
    defer assembler.deinit();

    const idx1 = try assembler.addConstant(.{ .integer = 42 });
    const idx2 = try assembler.addConstant(.{ .integer = 42 });
    const idx3 = try assembler.addConstant(.{ .integer = 100 });

    try std.testing.expectEqual(idx1, idx2);
    try std.testing.expect(idx1 != idx3);
}

test "instruction size calculation" {
    const small = Instruction{ .opcode = LOAD_CONST, .arg = 10 };
    const medium = Instruction{ .opcode = LOAD_CONST, .arg = 1000 };
    const large = Instruction{ .opcode = LOAD_CONST, .arg = 100000 };

    try std.testing.expectEqual(@as(usize, 2), small.size());
    try std.testing.expectEqual(@as(usize, 4), medium.size());
    try std.testing.expectEqual(@as(usize, 6), large.size());
}

test "basic assembly" {
    const allocator = std.testing.allocator;

    var assembler = Assembler.init(allocator);
    defer assembler.deinit();

    const block = try assembler.newBlock();
    assembler.setEntry(block);

    _ = try assembler.addConstant(.none);
    try assembler.emit(LOAD_CONST, 0);
    try assembler.emit(RETURN_VALUE, 0);

    const code = try assembler.assemble();
    defer allocator.free(code.bytecode);
    defer allocator.free(code.linetable);
    defer allocator.free(code.exception_table);
    defer allocator.free(code.constants);
    defer allocator.free(code.names);

    try std.testing.expectEqual(@as(usize, 4), code.bytecode.len);
}
