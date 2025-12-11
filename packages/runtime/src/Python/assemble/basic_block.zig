/// BasicBlock - Control Flow Graph Basic Block
/// Mirrors cpython/Python/assemble.c - basic block representation

const std = @import("std");
const Allocator = std.mem.Allocator;
const Instruction = @import("instruction.zig").Instruction;

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
