/// block - Basic Block Types
/// Mirrors cpython/Python/flowgraph.c - basic block implementation
///
/// A basic block contains a sequence of instructions with a single entry
/// and exit point. Control flow only branches at the end of a block.

const std = @import("std");
const Allocator = std.mem.Allocator;

// ============================================================================
// Basic Block
// ============================================================================

/// A basic block contains a sequence of instructions with a single entry
/// and exit point. Control flow only branches at the end of a block.
pub const BasicBlock = struct {
    const Self = @This();

    /// Block identifier
    id: u32,
    /// Instructions in this block
    instructions: std.ArrayList(Instruction),
    /// Successors (next blocks in control flow)
    successors: std.ArrayList(*Self),
    /// Predecessors (blocks that jump here)
    predecessors: std.ArrayList(*Self),
    /// Block is reachable from entry
    reachable: bool = false,
    /// Block has been visited (for graph traversal)
    visited: bool = false,
    /// Stack depth at block entry
    entry_stack_depth: i32 = -1,
    /// Stack depth at block exit
    exit_stack_depth: i32 = -1,
    /// Line number of first instruction
    start_line: i32 = 0,
    /// Exception handler block (if in try block)
    except_handler: ?*Self = null,
    /// Finally block (if in try-finally)
    finally_handler: ?*Self = null,
    /// Dominators (blocks that dominate this one)
    dominators: ?std.ArrayList(*Self) = null,
    /// Immediate dominator
    idom: ?*Self = null,
    /// Blocks this one dominates
    dominated: ?std.ArrayList(*Self) = null,
    /// Loop header if in a loop
    loop_header: ?*Self = null,
    /// Loop depth (0 = not in loop)
    loop_depth: u32 = 0,

    /// Memory allocator
    allocator: Allocator,

    /// Create a new basic block
    pub fn init(allocator: Allocator, id: u32) Self {
        return Self{
            .id = id,
            .instructions = .{},
            .successors = .{},
            .predecessors = .{},
            .allocator = allocator,
        };
    }

    /// Free basic block resources
    pub fn deinit(self: *Self) void {
        self.instructions.deinit(self.allocator);
        self.successors.deinit(self.allocator);
        self.predecessors.deinit(self.allocator);
        if (self.dominators) |*d| d.deinit(self.allocator);
        if (self.dominated) |*d| d.deinit(self.allocator);
    }

    /// Add instruction to block
    pub fn addInstruction(self: *Self, instr: Instruction) !void {
        try self.instructions.append(self.allocator, instr);
    }

    /// Add successor edge
    pub fn addSuccessor(self: *Self, succ: *Self) !void {
        // Avoid duplicates
        for (self.successors.items) |s| {
            if (s == succ) return;
        }
        try self.successors.append(self.allocator, succ);
        try succ.predecessors.append(succ.allocator, self);
    }

    /// Remove successor edge
    pub fn removeSuccessor(self: *Self, succ: *Self) void {
        // Remove from successors
        var i: usize = 0;
        while (i < self.successors.items.len) {
            if (self.successors.items[i] == succ) {
                _ = self.successors.orderedRemove(i);
            } else {
                i += 1;
            }
        }

        // Remove from predecessor's predecessors
        i = 0;
        while (i < succ.predecessors.items.len) {
            if (succ.predecessors.items[i] == self) {
                _ = succ.predecessors.orderedRemove(i);
            } else {
                i += 1;
            }
        }
    }

    /// Check if block is empty
    pub fn isEmpty(self: *const Self) bool {
        return self.instructions.items.len == 0;
    }

    /// Get last instruction
    pub fn lastInstruction(self: *Self) ?*Instruction {
        if (self.instructions.items.len == 0) return null;
        return &self.instructions.items[self.instructions.items.len - 1];
    }

    /// Check if block ends with unconditional jump
    pub fn endsWithUnconditionalJump(self: *Self) bool {
        if (self.lastInstruction()) |instr| {
            return instr.isUnconditionalJump();
        }
        return false;
    }

    /// Check if block ends with return
    pub fn endsWithReturn(self: *Self) bool {
        if (self.lastInstruction()) |instr| {
            return instr.opcode == .RETURN_VALUE or instr.opcode == .RETURN_CONST;
        }
        return false;
    }

    /// Calculate stack depth through block
    pub fn calculateStackDepth(self: *Self, entry_depth: i32) i32 {
        self.entry_stack_depth = entry_depth;
        var depth = entry_depth;

        for (self.instructions.items) |instr| {
            depth += instr.stackEffect();
        }

        self.exit_stack_depth = depth;
        return depth;
    }
};

// ============================================================================
// Instruction
// ============================================================================

/// Instruction in basic block
pub const Instruction = struct {
    /// Opcode
    opcode: Opcode,
    /// Argument
    arg: u32 = 0,
    /// Source line number
    lineno: i32 = 0,
    /// Column offset
    col_offset: i32 = 0,
    /// End line number
    end_lineno: i32 = 0,
    /// End column offset
    end_col_offset: i32 = 0,
    /// Jump target block
    target: ?*BasicBlock = null,

    /// Check if instruction is unconditional jump
    pub fn isUnconditionalJump(self: *const Instruction) bool {
        return self.opcode == .JUMP_FORWARD or
            self.opcode == .JUMP_BACKWARD or
            self.opcode == .JUMP_BACKWARD_NO_INTERRUPT;
    }

    /// Check if instruction is conditional jump
    pub fn isConditionalJump(self: *const Instruction) bool {
        return self.opcode == .POP_JUMP_IF_FALSE or
            self.opcode == .POP_JUMP_IF_TRUE or
            self.opcode == .JUMP_IF_FALSE_OR_POP or
            self.opcode == .JUMP_IF_TRUE_OR_POP or
            self.opcode == .FOR_ITER;
    }

    /// Check if instruction is any jump
    pub fn isJump(self: *const Instruction) bool {
        return self.isUnconditionalJump() or self.isConditionalJump();
    }

    /// Get stack effect
    pub fn stackEffect(self: *const Instruction) i32 {
        return switch (self.opcode) {
            .NOP => 0,
            .POP_TOP => -1,
            .PUSH_NULL => 1,
            .UNARY_NEGATIVE, .UNARY_NOT, .UNARY_INVERT => 0,
            .BINARY_OP, .BINARY_SUBSCR, .COMPARE_OP => -1,
            .STORE_SUBSCR => -3,
            .DELETE_SUBSCR => -2,
            .RETURN_VALUE => -1,
            .RETURN_CONST => 0,
            .LOAD_CONST, .LOAD_NAME, .LOAD_FAST, .LOAD_GLOBAL, .LOAD_DEREF => 1,
            .STORE_NAME, .STORE_FAST, .STORE_GLOBAL, .STORE_DEREF => -1,
            .STORE_ATTR => -2,
            .DELETE_ATTR => -1,
            .LOAD_ATTR => 0,
            .POP_JUMP_IF_FALSE, .POP_JUMP_IF_TRUE => -1,
            .JUMP_IF_FALSE_OR_POP, .JUMP_IF_TRUE_OR_POP => 0,
            .JUMP_FORWARD, .JUMP_BACKWARD, .JUMP_BACKWARD_NO_INTERRUPT => 0,
            .FOR_ITER => 1,
            .GET_ITER => 0,
            .BUILD_TUPLE, .BUILD_LIST, .BUILD_SET => 1 - @as(i32, @intCast(self.arg)),
            .BUILD_MAP => 1 - @as(i32, @intCast(2 * self.arg)),
            .CALL => -@as(i32, @intCast(self.arg)) - 1,
            else => 0,
        };
    }
};

// ============================================================================
// Opcode
// ============================================================================

/// Opcodes
pub const Opcode = enum(u8) {
    NOP = 0,
    POP_TOP = 1,
    PUSH_NULL = 2,
    END_FOR = 4,

    UNARY_NEGATIVE = 11,
    UNARY_NOT = 12,
    UNARY_INVERT = 15,

    BINARY_OP = 22,
    BINARY_SUBSCR = 25,

    STORE_SUBSCR = 60,
    DELETE_SUBSCR = 61,

    GET_ITER = 68,

    RETURN_VALUE = 83,
    RETURN_CONST = 121,

    STORE_NAME = 90,
    DELETE_NAME = 91,
    FOR_ITER = 93,

    STORE_ATTR = 95,
    DELETE_ATTR = 96,
    STORE_GLOBAL = 97,
    DELETE_GLOBAL = 98,

    LOAD_CONST = 100,
    LOAD_NAME = 101,
    BUILD_TUPLE = 102,
    BUILD_LIST = 103,
    BUILD_SET = 104,
    BUILD_MAP = 105,
    LOAD_ATTR = 106,
    COMPARE_OP = 107,

    JUMP_FORWARD = 110,
    JUMP_IF_FALSE_OR_POP = 111,
    JUMP_IF_TRUE_OR_POP = 112,
    POP_JUMP_IF_FALSE = 114,
    POP_JUMP_IF_TRUE = 115,
    LOAD_GLOBAL = 116,

    LOAD_FAST = 124,
    STORE_FAST = 125,
    DELETE_FAST = 126,

    JUMP_BACKWARD_NO_INTERRUPT = 134,
    LOAD_DEREF = 137,
    STORE_DEREF = 138,
    DELETE_DEREF = 139,
    JUMP_BACKWARD = 140,

    CALL = 171,
};
