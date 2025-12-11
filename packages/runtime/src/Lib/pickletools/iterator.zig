//! Opcode iterator for sequential pickle analysis.
//!
//! Provides iterator interface for traversing pickle data opcodes.
//! Mirrors: CPython Lib/pickletools.py - genops and OpcodeIterator

const std = @import("std");
const types = @import("types.zig");

pub const Opcode = types.Opcode;
pub const OpcodeInfo = types.OpcodeInfo;

/// Iterator over pickle opcodes
pub const OpcodeIterator = struct {
    const Self = @This();

    data: []const u8,
    pos: usize,

    pub fn init(data: []const u8) Self {
        return .{ .data = data, .pos = 0 };
    }

    pub fn next(self: *Self) ?OpcodeInfo {
        if (self.pos >= self.data.len) return null;

        const start_pos = self.pos;
        const op: Opcode = @enumFromInt(self.data[self.pos]);
        self.pos += 1;

        var arg: ?OpcodeInfo.Argument = null;

        // Parse argument based on opcode
        switch (op) {
            .PROTO => {
                if (self.pos < self.data.len) {
                    arg = .{ .uint = self.data[self.pos] };
                    self.pos += 1;
                }
            },
            .BININT1 => {
                if (self.pos < self.data.len) {
                    arg = .{ .uint = self.data[self.pos] };
                    self.pos += 1;
                }
            },
            .BININT2 => {
                if (self.pos + 2 <= self.data.len) {
                    arg = .{ .uint = std.mem.readInt(u16, self.data[self.pos..][0..2], .little) };
                    self.pos += 2;
                }
            },
            .BININT => {
                if (self.pos + 4 <= self.data.len) {
                    arg = .{ .int = std.mem.readInt(i32, self.data[self.pos..][0..4], .little) };
                    self.pos += 4;
                }
            },
            else => {
                arg = .none;
            },
        }

        return OpcodeInfo{
            .opcode = op,
            .arg = arg,
            .pos = start_pos,
            .proto = op.protocol(),
        };
    }
};

/// Generate opcode sequence from pickle data
pub fn genops(data: []const u8) OpcodeIterator {
    return OpcodeIterator.init(data);
}
