/// quicken - Code Quickening
/// Bytecode quickening and warmup counter initialization.

const std = @import("std");
const types = @import("types.zig");
const opcodes = @import("opcodes.zig");

pub const BackoffCounter = types.BackoffCounter;
pub const CodeUnit = opcodes.CodeUnit;
pub const getOpcodeCaches = opcodes.getOpcodeCaches;

// ============================================================================
// Code Quickening
// ============================================================================

/// Quicken bytecode - initialize warmup counters
pub fn quickenCode(instructions: []CodeUnit, enable_counters: bool) void {
    const jump_counter = if (enable_counters) BackoffCounter.jumpBackoff() else BackoffCounter.@"unreachable"();
    const adaptive_counter = if (enable_counters) BackoffCounter.warmup() else BackoffCounter.@"unreachable"();

    var i: usize = 0;
    var oparg: u32 = 0;

    while (i < instructions.len -| 1) : (i += 1) {
        const opcode = instructions[i].op;
        const caches = getOpcodeCaches(opcode);
        oparg = (oparg << 8) | instructions[i].arg;

        if (caches > 0) {
            // Initialize cache based on opcode
            const counter: BackoffCounter = switch (opcode) {
                // JUMP_BACKWARD
                140 => jump_counter,
                // POP_JUMP_IF_* variants
                114, 115, 128, 129 => blk: {
                    // Set alternating pattern for branch prediction
                    const cache_ptr = @as(*u16, @ptrCast(&instructions[i + 1]));
                    cache_ptr.* = 0x5555;
                    break :blk adaptive_counter;
                },
                else => adaptive_counter,
            };

            // Store counter in next instruction slot
            const counter_ptr = @as(*BackoffCounter, @ptrCast(&instructions[i + 1]));
            counter_ptr.* = counter;

            i += caches;
        }

        // Reset oparg after non-EXTENDED_ARG
        if (opcode != 144) { // EXTENDED_ARG
            oparg = 0;
        }
    }
}

// ============================================================================
// Tests
// ============================================================================

test "quicken code" {
    var instructions = [_]CodeUnit{
        .{ .op = 106, .arg = 0 }, // LOAD_ATTR
        .{ .op = 0, .arg = 0 }, // cache slot 1
        .{ .op = 0, .arg = 0 }, // cache slot 2
        .{ .op = 0, .arg = 0 }, // cache slot 3
        .{ .op = 0, .arg = 0 }, // cache slot 4
        .{ .op = 0, .arg = 0 }, // cache slot 5
        .{ .op = 0, .arg = 0 }, // cache slot 6
        .{ .op = 0, .arg = 0 }, // cache slot 7
        .{ .op = 0, .arg = 0 }, // cache slot 8
        .{ .op = 0, .arg = 0 }, // cache slot 9
        .{ .op = 1, .arg = 0 }, // POP_TOP (end marker)
    };

    quickenCode(&instructions, true);

    // First cache slot should have counter initialized
    const counter_ptr = @as(*BackoffCounter, @ptrCast(&instructions[1]));
    try std.testing.expect(counter_ptr.value > 0);
}
