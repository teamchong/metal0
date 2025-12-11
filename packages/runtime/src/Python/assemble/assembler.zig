/// Assembler - Core Assembler State and Operations
/// Mirrors cpython/Python/assemble.c - assembler implementation

const std = @import("std");
const Allocator = std.mem.Allocator;
const BasicBlock = @import("basic_block.zig").BasicBlock;
const instruction = @import("instruction.zig");
const types = @import("types.zig");
const pipeline = @import("pipeline.zig");

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
    exception_table: std.ArrayList(types.ExceptionEntry),
    /// Constants pool
    constants: std.ArrayList(types.Constant),
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
            .exception_table = std.ArrayList(types.ExceptionEntry).init(allocator),
            .constants = std.ArrayList(types.Constant).init(allocator),
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
    pub fn addConstant(self: *Self, constant: types.Constant) !u32 {
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
    pub fn assemble(self: *Self) !types.AssembledCode {
        // Phase 1: Mark reachable blocks
        try pipeline.markReachable(self);

        // Phase 2: Calculate block offsets
        try pipeline.calculateOffsets(self);

        // Phase 3: Resolve jumps and emit bytecode
        try pipeline.emitBytecode(self);

        // Phase 4: Generate line number table
        try pipeline.generateLinetable(self);

        // Phase 5: Generate exception table
        try pipeline.generateExceptionTable(self);

        return types.AssembledCode{
            .bytecode = try self.allocator.dupe(u8, self.bytecode.items),
            .linetable = try self.allocator.dupe(u8, self.linetable.items),
            .exception_table = try self.allocator.dupe(types.ExceptionEntry, self.exception_table.items),
            .constants = try self.allocator.dupe(types.Constant, self.constants.items),
            .names = try self.allocator.dupe([]const u8, self.names.items),
            .stack_size = self.stack_size,
            .num_locals = self.num_locals,
        };
    }
};
