/// _opcode_metadata/lookup.zig - Opcode lookup functions
/// Provides runtime lookup of opcode definitions by code or name using
/// comptime introspection.

const std = @import("std");
const opcodes_mod = @import("opcodes.zig");

pub const OpcodeDef = opcodes_mod.OpcodeDef;
pub const opcodes = opcodes_mod.opcodes;

/// Get opcode by code
pub fn getOpcode(code: u8) ?OpcodeDef {
    // In a full implementation, this would be a lookup table
    inline for (@typeInfo(opcodes).@"struct".decls) |decl| {
        const op = @field(opcodes, decl.name);
        if (@TypeOf(op) == OpcodeDef and op.code == code) {
            return op;
        }
    }
    return null;
}

/// Get opcode by name
pub fn getOpcodeByName(name: []const u8) ?OpcodeDef {
    inline for (@typeInfo(opcodes).@"struct".decls) |decl| {
        const op = @field(opcodes, decl.name);
        if (@TypeOf(op) == OpcodeDef and std.mem.eql(u8, op.name, name)) {
            return op;
        }
    }
    return null;
}

test "get opcode by code" {
    if (getOpcode(100)) |op| {
        try std.testing.expectEqualStrings("LOAD_CONST", op.name);
    } else {
        return error.TestFailed;
    }
}

test "get opcode by name" {
    if (getOpcodeByName("RETURN_VALUE")) |op| {
        try std.testing.expectEqual(@as(u8, 83), op.code);
    } else {
        return error.TestFailed;
    }
}
