//! CPython source: Lib/pickletools.py
//!
//! Provides functions to analyze and disassemble pickle data.
//!
//! Mirrors: CPython Lib/pickletools.py

const pickletools = @import("pickletools/opcode.zig");
const types_module = @import("pickletools/types.zig");
const iterator_module = @import("pickletools/iterator.zig");
const disassembler_module = @import("pickletools/disassembler.zig");
const optimizer_module = @import("pickletools/optimizer.zig");
const protocol_module = @import("pickletools/protocol.zig");

// Re-export opcodes and types
pub const Opcode = pickletools.Opcode;
pub const OpcodeInfo = types_module.OpcodeInfo;

// Re-export iterator
pub const OpcodeIterator = iterator_module.OpcodeIterator;
pub const genops = iterator_module.genops;

// Re-export disassembler
pub const dis = disassembler_module.dis;

// Re-export optimizer
pub const optimize = optimizer_module.optimize;

// Re-export protocol detection
pub const getProtocol = protocol_module.getProtocol;

// ============================================================================
// Tests
// ============================================================================

const std = @import("std");

test "Opcode names" {
    try std.testing.expectEqualStrings("MARK", Opcode.MARK.name());
    try std.testing.expectEqualStrings("STOP", Opcode.STOP.name());
    try std.testing.expectEqualStrings("PROTO", Opcode.PROTO.name());
    try std.testing.expectEqualStrings("NONE", Opcode.NONE.name());
}

test "Opcode protocol versions" {
    try std.testing.expectEqual(@as(u8, 0), Opcode.MARK.protocol());
    try std.testing.expectEqual(@as(u8, 2), Opcode.PROTO.protocol());
    try std.testing.expectEqual(@as(u8, 3), Opcode.BINBYTES.protocol());
    try std.testing.expectEqual(@as(u8, 4), Opcode.FRAME.protocol());
    try std.testing.expectEqual(@as(u8, 5), Opcode.BYTEARRAY8.protocol());
}

test "getProtocol" {
    // Protocol 2 pickle
    const pickle2 = [_]u8{ 0x80, 0x02, '.' };
    try std.testing.expectEqual(@as(u8, 2), getProtocol(&pickle2));

    // Protocol 0 pickle (no PROTO opcode)
    const pickle0 = [_]u8{ 'N', '.' };
    try std.testing.expectEqual(@as(u8, 0), getProtocol(&pickle0));
}

test "OpcodeIterator" {
    const pickle = [_]u8{ 0x80, 0x03, 'N', '.' };
    var iter = genops(&pickle);

    const op1 = iter.next().?;
    try std.testing.expectEqual(Opcode.PROTO, op1.opcode);
    try std.testing.expectEqual(@as(u64, 3), op1.arg.?.uint);

    const op2 = iter.next().?;
    try std.testing.expectEqual(Opcode.NONE, op2.opcode);

    const op3 = iter.next().?;
    try std.testing.expectEqual(Opcode.STOP, op3.opcode);

    try std.testing.expect(iter.next() == null);
}

test "optimize" {
    const allocator = std.testing.allocator;
    const pickle = [_]u8{ 0x80, 0x03, 'N', '.' };
    const result = try optimize(allocator, &pickle);
    defer allocator.free(result);

    try std.testing.expect(std.mem.indexOf(u8, result, "statistics") != null);
}
