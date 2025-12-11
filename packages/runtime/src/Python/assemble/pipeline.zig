/// Pipeline - Assembly Pipeline Phases
/// Mirrors cpython/Python/assemble.c - assembly process

const std = @import("std");
const Allocator = std.mem.Allocator;
const BasicBlock = @import("basic_block.zig").BasicBlock;
const instruction = @import("instruction.zig");
const types = @import("types.zig");

// Forward declare Assembler to avoid circular dependency
const Assembler = @import("assembler.zig").Assembler;

/// Mark reachable blocks starting from entry
pub fn markReachable(assembler: *Assembler) !void {
    if (assembler.entry_block == null) return;

    var worklist = std.ArrayList(*BasicBlock).init(assembler.allocator);
    defer worklist.deinit();

    // Reset visited flags
    for (assembler.blocks.items) |block| {
        block.visited = false;
        block.reachable = false;
    }

    try worklist.append(assembler.entry_block.?);
    assembler.entry_block.?.reachable = true;

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
pub fn calculateOffsets(assembler: *Assembler) !void {
    var offset: u32 = 0;
    for (assembler.blocks.items) |block| {
        if (!block.reachable) continue;
        block.offset = offset;
        offset += @intCast(block.byteSize());
    }
}

/// Emit bytecode for all blocks
pub fn emitBytecode(assembler: *Assembler) !void {
    for (assembler.blocks.items) |block| {
        if (!block.reachable) continue;

        for (block.instructions.items) |instr| {
            try emitInstruction(assembler, instr, block.offset);
        }
    }
}

/// Emit single instruction to bytecode
fn emitInstruction(assembler: *Assembler, instr: instruction.Instruction, block_offset: u32) !void {
    var arg = instr.arg;

    // Resolve jump target
    if (instr.target) |target| {
        if (instr.opcode == instruction.JUMP_FORWARD) {
            // Relative jump
            arg = target.offset -| (block_offset + 2);
        } else {
            // Absolute jump
            arg = target.offset;
        }
    }

    // Emit EXTENDED_ARG if needed
    if (arg >= 0x1000000) {
        try assembler.bytecode.append(instruction.EXTENDED_ARG);
        try assembler.bytecode.append(@truncate(arg >> 24));
    }
    if (arg >= 0x10000) {
        try assembler.bytecode.append(instruction.EXTENDED_ARG);
        try assembler.bytecode.append(@truncate(arg >> 16));
    }
    if (arg >= instruction.EXTENDED_ARG_THRESHOLD) {
        try assembler.bytecode.append(instruction.EXTENDED_ARG);
        try assembler.bytecode.append(@truncate(arg >> 8));
    }

    // Emit opcode and arg
    try assembler.bytecode.append(instr.opcode);
    try assembler.bytecode.append(@truncate(arg));
}

/// Generate line number table (Python 3.11+ format)
pub fn generateLinetable(assembler: *Assembler) !void {
    var prev_lineno: i32 = 0;

    for (assembler.blocks.items) |block| {
        if (!block.reachable) continue;

        for (block.instructions.items) |instr| {
            if (instr.lineno != prev_lineno and instr.lineno > 0) {
                const delta = instr.lineno - prev_lineno;
                try encodeLineDelta(assembler, delta);
                prev_lineno = instr.lineno;
            }
        }
    }
}

/// Encode line number delta
fn encodeLineDelta(assembler: *Assembler, delta: i32) !void {
    if (delta >= -128 and delta <= 127) {
        // Single byte encoding
        try assembler.linetable.append(@bitCast(@as(i8, @intCast(delta))));
    } else {
        // Extended encoding
        try assembler.linetable.append(0xFF);
        try assembler.linetable.append(@bitCast(@as(i8, @intCast(@divTrunc(delta, 256)))));
        try assembler.linetable.append(@truncate(@as(u32, @bitCast(delta))));
    }
}

/// Generate exception handler table
pub fn generateExceptionTable(assembler: *Assembler) !void {
    for (assembler.blocks.items) |block| {
        if (!block.reachable) continue;
        if (block.except_handler) |handler| {
            try assembler.exception_table.append(.{
                .start = block.offset,
                .end = block.offset + @as(u32, @intCast(block.byteSize())),
                .target = handler.offset,
                .depth = @intCast(block.stack_depth),
                .lasti = false,
            });
        }
    }
}
