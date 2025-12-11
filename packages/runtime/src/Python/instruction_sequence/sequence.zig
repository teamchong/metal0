/// InstructionSequence - Builder for bytecode
/// Provides builder pattern for constructing bytecode with labels and jumps

const std = @import("std");
const Allocator = std.mem.Allocator;
const types = @import("types.zig");
const stack_effects = @import("stack_effects.zig");

pub const Instruction = types.Instruction;
pub const LabelId = types.LabelId;
pub const Label = types.Label;
pub const ExceptionHandler = types.ExceptionHandler;

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
        const delta = stack_effects.getStackEffect(opcode, arg);
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
