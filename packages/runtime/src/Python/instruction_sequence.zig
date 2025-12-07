/// instruction_sequence - Instruction Sequence
/// Mirrors cpython/Python/instruction_sequence.c
///
/// Manages sequences of bytecode instructions during compilation.
/// Provides builder pattern for constructing bytecode with labels and jumps.

const std = @import("std");
const Allocator = std.mem.Allocator;

// ============================================================================
// Instruction Types
// ============================================================================

/// Bytecode instruction
pub const Instruction = struct {
    /// Opcode
    opcode: u8,
    /// Argument (or 0 if none)
    arg: u32 = 0,
    /// Line number in source
    lineno: u32 = 0,
    /// Column offset
    col_offset: u16 = 0,
    /// End column offset
    end_col_offset: u16 = 0,
    /// Jump target label (if branch)
    target: ?LabelId = null,
};

/// Label identifier
pub const LabelId = u32;

/// Special label values
pub const LABEL_NONE: LabelId = std.math.maxInt(LabelId);

/// Label entry
pub const Label = struct {
    /// Label ID
    id: LabelId,
    /// Byte offset (filled during resolution)
    offset: ?usize = null,
    /// Whether label has been placed
    placed: bool = false,
};

// ============================================================================
// Exception Handler
// ============================================================================

/// Exception handler entry
pub const ExceptionHandler = struct {
    /// Start offset (instruction index)
    start: usize,
    /// End offset
    end: usize,
    /// Handler offset
    handler: usize,
    /// Stack depth at handler
    depth: u16 = 0,
    /// Exception type (or null for bare except)
    type_name: ?[]const u8 = null,
};

// ============================================================================
// Instruction Sequence
// ============================================================================

/// Sequence of instructions (builder for bytecode)
pub const InstructionSequence = struct {
    const Self = @This();

    /// Instructions
    instructions: std.ArrayList(Instruction),
    /// Labels
    labels: std.AutoHashMap(LabelId, Label),
    /// Exception handlers
    handlers: std.ArrayList(ExceptionHandler),
    /// Next label ID
    next_label_id: LabelId = 0,
    /// Current line number
    current_lineno: u32 = 1,
    /// Current column offset
    current_col: u16 = 0,
    /// Stack depth tracking
    stack_depth: i32 = 0,
    /// Maximum stack depth seen
    max_stack_depth: i32 = 0,
    /// Allocator
    allocator: Allocator,

    pub fn init(allocator: Allocator) Self {
        return Self{
            .allocator = allocator,
            .instructions = std.ArrayList(Instruction).init(allocator),
            .labels = std.AutoHashMap(LabelId, Label).init(allocator),
            .handlers = std.ArrayList(ExceptionHandler).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.instructions.deinit();
        self.labels.deinit();
        self.handlers.deinit();
    }

    /// Set current source location
    pub fn setLocation(self: *Self, lineno: u32, col_offset: u16, end_col_offset: u16) void {
        self.current_lineno = lineno;
        self.current_col = col_offset;
        _ = end_col_offset;
    }

    /// Create a new label
    pub fn newLabel(self: *Self) !LabelId {
        const id = self.next_label_id;
        self.next_label_id += 1;

        try self.labels.put(id, .{ .id = id });
        return id;
    }

    /// Place a label at current position
    pub fn placeLabel(self: *Self, label_id: LabelId) !void {
        if (self.labels.getPtr(label_id)) |label| {
            label.offset = self.instructions.items.len;
            label.placed = true;
        } else {
            return error.InvalidLabel;
        }
    }

    /// Add instruction with no argument
    pub fn addOp(self: *Self, opcode: u8) !void {
        try self.addOpArg(opcode, 0);
    }

    /// Add instruction with argument
    pub fn addOpArg(self: *Self, opcode: u8, arg: u32) !void {
        try self.instructions.append(.{
            .opcode = opcode,
            .arg = arg,
            .lineno = self.current_lineno,
            .col_offset = self.current_col,
        });
        self.updateStackDepth(opcode, arg);
    }

    /// Add jump instruction
    pub fn addJump(self: *Self, opcode: u8, target: LabelId) !void {
        try self.instructions.append(.{
            .opcode = opcode,
            .arg = 0,
            .lineno = self.current_lineno,
            .col_offset = self.current_col,
            .target = target,
        });
        self.updateStackDepth(opcode, 0);
    }

    /// Update stack depth based on opcode
    fn updateStackDepth(self: *Self, opcode: u8, arg: u32) void {
        const delta = getStackEffect(opcode, arg);
        self.stack_depth += delta;
        if (self.stack_depth > self.max_stack_depth) {
            self.max_stack_depth = self.stack_depth;
        }
    }

    /// Add exception handler
    pub fn addHandler(self: *Self, start: usize, end: usize, handler: usize) !void {
        try self.handlers.append(.{
            .start = start,
            .end = end,
            .handler = handler,
            .depth = @intCast(@max(0, self.stack_depth)),
        });
    }

    /// Get number of instructions
    pub fn length(self: *const Self) usize {
        return self.instructions.items.len;
    }

    /// Get instruction at index
    pub fn get(self: *const Self, index: usize) ?Instruction {
        if (index < self.instructions.items.len) {
            return self.instructions.items[index];
        }
        return null;
    }

    /// Resolve all jump targets
    pub fn resolveJumps(self: *Self) !void {
        for (self.instructions.items) |*inst| {
            if (inst.target) |label_id| {
                if (self.labels.get(label_id)) |label| {
                    if (label.offset) |offset| {
                        inst.arg = @intCast(offset);
                    } else {
                        return error.UnplacedLabel;
                    }
                } else {
                    return error.InvalidLabel;
                }
            }
        }
    }

    /// Convert to bytecode
    pub fn toBytecode(self: *Self, allocator: Allocator) ![]u8 {
        try self.resolveJumps();

        // Simple bytecode format: opcode (1 byte) + arg (4 bytes)
        const code = try allocator.alloc(u8, self.instructions.items.len * 5);

        for (self.instructions.items, 0..) |inst, i| {
            const offset = i * 5;
            code[offset] = inst.opcode;
            std.mem.writeInt(u32, code[offset + 1 ..][0..4], inst.arg, .little);
        }

        return code;
    }

    /// Clear all instructions
    pub fn clear(self: *Self) void {
        self.instructions.clearRetainingCapacity();
        self.labels.clearRetainingCapacity();
        self.handlers.clearRetainingCapacity();
        self.next_label_id = 0;
        self.stack_depth = 0;
        self.max_stack_depth = 0;
    }
};

// ============================================================================
// Stack Effect Table
// ============================================================================

/// Get stack effect of opcode
pub fn getStackEffect(opcode: u8, arg: u32) i32 {
    // Common opcodes and their stack effects
    return switch (opcode) {
        // Push operations
        1 => 1, // LOAD_CONST
        2 => 1, // LOAD_NAME
        3 => 1, // LOAD_FAST
        4 => 1, // LOAD_GLOBAL
        5 => 1, // LOAD_ATTR (+1, but pops obj)

        // Pop operations
        10 => -1, // POP_TOP
        11 => -1, // STORE_NAME
        12 => -1, // STORE_FAST
        13 => -1, // STORE_GLOBAL
        14 => -2, // STORE_ATTR

        // Binary operations (pop 2, push 1)
        20 => -1, // BINARY_ADD
        21 => -1, // BINARY_SUBTRACT
        22 => -1, // BINARY_MULTIPLY
        23 => -1, // BINARY_DIVIDE
        24 => -1, // BINARY_MODULO
        25 => -1, // BINARY_POWER

        // Unary operations (pop 1, push 1)
        30 => 0, // UNARY_NEGATIVE
        31 => 0, // UNARY_NOT
        32 => 0, // UNARY_INVERT

        // Comparison (pop 2, push 1)
        40 => -1, // COMPARE_OP

        // Jumps (no stack effect for unconditional)
        50 => 0, // JUMP_ABSOLUTE
        51 => -1, // JUMP_IF_FALSE_OR_POP
        52 => -1, // JUMP_IF_TRUE_OR_POP
        53 => -1, // POP_JUMP_IF_FALSE
        54 => -1, // POP_JUMP_IF_TRUE

        // Function calls
        60 => -@as(i32, @intCast(arg)), // CALL_FUNCTION (pops func + args, pushes result)

        // Return
        70 => -1, // RETURN_VALUE

        // Build operations
        80 => 1 - @as(i32, @intCast(arg)), // BUILD_TUPLE
        81 => 1 - @as(i32, @intCast(arg)), // BUILD_LIST
        82 => 1 - @as(i32, @intCast(arg)) * 2, // BUILD_MAP

        // Default: no effect
        else => 0,
    };
}

// ============================================================================
// Opcodes (subset for reference)
// ============================================================================

pub const Opcode = struct {
    pub const LOAD_CONST: u8 = 1;
    pub const LOAD_NAME: u8 = 2;
    pub const LOAD_FAST: u8 = 3;
    pub const LOAD_GLOBAL: u8 = 4;
    pub const LOAD_ATTR: u8 = 5;

    pub const POP_TOP: u8 = 10;
    pub const STORE_NAME: u8 = 11;
    pub const STORE_FAST: u8 = 12;
    pub const STORE_GLOBAL: u8 = 13;
    pub const STORE_ATTR: u8 = 14;

    pub const BINARY_ADD: u8 = 20;
    pub const BINARY_SUBTRACT: u8 = 21;
    pub const BINARY_MULTIPLY: u8 = 22;
    pub const BINARY_DIVIDE: u8 = 23;
    pub const BINARY_MODULO: u8 = 24;
    pub const BINARY_POWER: u8 = 25;

    pub const UNARY_NEGATIVE: u8 = 30;
    pub const UNARY_NOT: u8 = 31;
    pub const UNARY_INVERT: u8 = 32;

    pub const COMPARE_OP: u8 = 40;

    pub const JUMP_ABSOLUTE: u8 = 50;
    pub const JUMP_IF_FALSE_OR_POP: u8 = 51;
    pub const JUMP_IF_TRUE_OR_POP: u8 = 52;
    pub const POP_JUMP_IF_FALSE: u8 = 53;
    pub const POP_JUMP_IF_TRUE: u8 = 54;

    pub const CALL_FUNCTION: u8 = 60;

    pub const RETURN_VALUE: u8 = 70;

    pub const BUILD_TUPLE: u8 = 80;
    pub const BUILD_LIST: u8 = 81;
    pub const BUILD_MAP: u8 = 82;

    pub const NOP: u8 = 0;
};

// ============================================================================
// Line Number Table
// ============================================================================

/// Line number table builder
pub const LineNumberTable = struct {
    const Self = @This();

    /// Entries: (instruction offset, line number)
    entries: std.ArrayList(struct { offset: usize, line: u32 }),
    /// Last line recorded
    last_line: u32 = 0,
    /// Allocator
    allocator: Allocator,

    pub fn init(allocator: Allocator) Self {
        return Self{
            .allocator = allocator,
            .entries = std.ArrayList(struct { offset: usize, line: u32 }).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.entries.deinit();
    }

    /// Add line number entry
    pub fn addEntry(self: *Self, offset: usize, line: u32) !void {
        if (line != self.last_line) {
            try self.entries.append(.{ .offset = offset, .line = line });
            self.last_line = line;
        }
    }

    /// Find line number for offset
    pub fn findLine(self: *const Self, offset: usize) u32 {
        var line: u32 = 0;
        for (self.entries.items) |entry| {
            if (entry.offset > offset) break;
            line = entry.line;
        }
        return line;
    }
};

// ============================================================================
// Module State
// ============================================================================

var initialized: bool = false;

/// Initialize the instruction_sequence module
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

test "instruction struct" {
    const inst = Instruction{
        .opcode = Opcode.LOAD_CONST,
        .arg = 42,
        .lineno = 10,
    };
    try std.testing.expectEqual(@as(u8, 1), inst.opcode);
    try std.testing.expectEqual(@as(u32, 42), inst.arg);
}

test "instruction sequence basic" {
    const allocator = std.testing.allocator;
    var seq = InstructionSequence.init(allocator);
    defer seq.deinit();

    try seq.addOpArg(Opcode.LOAD_CONST, 1);
    try seq.addOpArg(Opcode.LOAD_CONST, 2);
    try seq.addOpArg(Opcode.BINARY_ADD, 0);
    try seq.addOp(Opcode.RETURN_VALUE);

    try std.testing.expectEqual(@as(usize, 4), seq.length());
}

test "label creation and placement" {
    const allocator = std.testing.allocator;
    var seq = InstructionSequence.init(allocator);
    defer seq.deinit();

    const label = try seq.newLabel();
    try seq.addOpArg(Opcode.LOAD_CONST, 0);
    try seq.placeLabel(label);
    try seq.addOp(Opcode.RETURN_VALUE);

    const placed_label = seq.labels.get(label);
    try std.testing.expect(placed_label != null);
    try std.testing.expect(placed_label.?.placed);
    try std.testing.expectEqual(@as(?usize, 1), placed_label.?.offset);
}

test "jump resolution" {
    const allocator = std.testing.allocator;
    var seq = InstructionSequence.init(allocator);
    defer seq.deinit();

    const end_label = try seq.newLabel();
    try seq.addJump(Opcode.JUMP_ABSOLUTE, end_label);
    try seq.addOpArg(Opcode.LOAD_CONST, 1);
    try seq.placeLabel(end_label);
    try seq.addOp(Opcode.RETURN_VALUE);

    try seq.resolveJumps();

    // Jump should point to instruction 2
    try std.testing.expectEqual(@as(u32, 2), seq.instructions.items[0].arg);
}

test "stack depth tracking" {
    const allocator = std.testing.allocator;
    var seq = InstructionSequence.init(allocator);
    defer seq.deinit();

    try seq.addOpArg(Opcode.LOAD_CONST, 1); // +1
    try seq.addOpArg(Opcode.LOAD_CONST, 2); // +1
    try seq.addOp(Opcode.BINARY_ADD); // -1
    try seq.addOp(Opcode.RETURN_VALUE); // -1

    try std.testing.expectEqual(@as(i32, 2), seq.max_stack_depth);
    try std.testing.expectEqual(@as(i32, 0), seq.stack_depth);
}

test "bytecode generation" {
    const allocator = std.testing.allocator;
    var seq = InstructionSequence.init(allocator);
    defer seq.deinit();

    try seq.addOpArg(Opcode.LOAD_CONST, 42);
    try seq.addOp(Opcode.RETURN_VALUE);

    const bytecode = try seq.toBytecode(allocator);
    defer allocator.free(bytecode);

    try std.testing.expectEqual(@as(usize, 10), bytecode.len); // 2 instructions * 5 bytes
    try std.testing.expectEqual(Opcode.LOAD_CONST, bytecode[0]);
}

test "line number table" {
    const allocator = std.testing.allocator;
    var table = LineNumberTable.init(allocator);
    defer table.deinit();

    try table.addEntry(0, 1);
    try table.addEntry(3, 2);
    try table.addEntry(5, 3);

    try std.testing.expectEqual(@as(u32, 1), table.findLine(0));
    try std.testing.expectEqual(@as(u32, 1), table.findLine(2));
    try std.testing.expectEqual(@as(u32, 2), table.findLine(3));
    try std.testing.expectEqual(@as(u32, 3), table.findLine(10));
}

test "stack effects" {
    try std.testing.expectEqual(@as(i32, 1), getStackEffect(Opcode.LOAD_CONST, 0));
    try std.testing.expectEqual(@as(i32, -1), getStackEffect(Opcode.POP_TOP, 0));
    try std.testing.expectEqual(@as(i32, -1), getStackEffect(Opcode.BINARY_ADD, 0));
    try std.testing.expectEqual(@as(i32, 0), getStackEffect(Opcode.JUMP_ABSOLUTE, 0));
}
