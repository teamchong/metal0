/// Compiled bytecode program with serialization support
const std = @import("std");
const constants = @import("constants.zig");
const Instruction = constants.Instruction;
const Constant = constants.Constant;

/// Compiled bytecode program
pub const BytecodeProgram = struct {
    instructions: []Instruction,
    constants: []Constant,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *BytecodeProgram) void {
        self.allocator.free(self.instructions);
        self.allocator.free(self.constants);
    }

    /// Serialize bytecode to binary format for subprocess IPC
    /// Format: [magic][version][num_constants][constants...][num_instructions][instructions...]
    pub fn serialize(self: *const BytecodeProgram, allocator: std.mem.Allocator) ![]u8 {
        var buffer = std.ArrayList(u8).init(allocator);
        errdefer buffer.deinit();

        // Magic: "PYBC" (4 bytes)
        try buffer.appendSlice("PYBC");

        // Version: 1 (4 bytes, little endian)
        try buffer.appendSlice(&std.mem.toBytes(@as(u32, 1)));

        // Number of constants (4 bytes)
        try buffer.appendSlice(&std.mem.toBytes(@as(u32, @intCast(self.constants.len))));

        // Constants
        for (self.constants) |constant| {
            switch (constant) {
                .int => |i| {
                    try buffer.append(0); // type tag: int
                    try buffer.appendSlice(&std.mem.toBytes(i));
                },
                .float => |f| {
                    try buffer.append(2); // type tag: float
                    try buffer.appendSlice(&std.mem.toBytes(f));
                },
                .string => |s| {
                    try buffer.append(1); // type tag: string
                    try buffer.appendSlice(&std.mem.toBytes(@as(u32, @intCast(s.len))));
                    try buffer.appendSlice(s);
                },
                .bool => |b| {
                    try buffer.append(3); // type tag: bool
                    try buffer.append(if (b) 1 else 0);
                },
                .bigint => |s| {
                    try buffer.append(4); // type tag: bigint (stored as string)
                    try buffer.appendSlice(&std.mem.toBytes(@as(u32, @intCast(s.len))));
                    try buffer.appendSlice(s);
                },
                .complex => |c| {
                    try buffer.append(6); // type tag: complex
                    try buffer.appendSlice(&std.mem.toBytes(c));
                },
            }
        }

        // Number of instructions (4 bytes)
        try buffer.appendSlice(&std.mem.toBytes(@as(u32, @intCast(self.instructions.len))));

        // Instructions (5 bytes each: 1 opcode + 4 arg)
        for (self.instructions) |inst| {
            try buffer.append(@intFromEnum(inst.op));
            try buffer.appendSlice(&std.mem.toBytes(inst.arg));
        }

        return buffer.toOwnedSlice();
    }

    /// Deserialize bytecode from binary format (subprocess output)
    pub fn deserialize(allocator: std.mem.Allocator, data: []const u8) !BytecodeProgram {
        if (data.len < 12) return error.InvalidBytecode; // magic + version + num_constants

        var pos: usize = 0;

        // Check magic
        if (!std.mem.eql(u8, data[0..4], "PYBC")) return error.InvalidMagic;
        pos += 4;

        // Check version
        const version = std.mem.readInt(u32, data[pos..][0..4], .little);
        if (version != 1) return error.UnsupportedVersion;
        pos += 4;

        // Read constants
        const num_constants = std.mem.readInt(u32, data[pos..][0..4], .little);
        pos += 4;

        var consts = try allocator.alloc(Constant, num_constants);
        errdefer allocator.free(consts);

        for (0..num_constants) |i| {
            if (pos >= data.len) return error.UnexpectedEof;
            const type_tag = data[pos];
            pos += 1;

            switch (type_tag) {
                0 => { // int
                    if (pos + 8 > data.len) return error.UnexpectedEof;
                    consts[i] = .{ .int = std.mem.readInt(i64, data[pos..][0..8], .little) };
                    pos += 8;
                },
                1 => { // string
                    if (pos + 4 > data.len) return error.UnexpectedEof;
                    const str_len = std.mem.readInt(u32, data[pos..][0..4], .little);
                    pos += 4;
                    if (pos + str_len > data.len) return error.UnexpectedEof;
                    consts[i] = .{ .string = try allocator.dupe(u8, data[pos..][0..str_len]) };
                    pos += str_len;
                },
                2 => { // float
                    if (pos + 8 > data.len) return error.UnexpectedEof;
                    consts[i] = .{ .float = @bitCast(std.mem.readInt(u64, data[pos..][0..8], .little)) };
                    pos += 8;
                },
                3 => { // bool
                    if (pos + 1 > data.len) return error.UnexpectedEof;
                    consts[i] = .{ .bool = data[pos] != 0 };
                    pos += 1;
                },
                4 => { // bigint (stored as string)
                    if (pos + 4 > data.len) return error.UnexpectedEof;
                    const str_len = std.mem.readInt(u32, data[pos..][0..4], .little);
                    pos += 4;
                    if (pos + str_len > data.len) return error.UnexpectedEof;
                    consts[i] = .{ .bigint = try allocator.dupe(u8, data[pos..][0..str_len]) };
                    pos += str_len;
                },
                6 => { // complex
                    if (pos + 8 > data.len) return error.UnexpectedEof;
                    consts[i] = .{ .complex = @bitCast(std.mem.readInt(u64, data[pos..][0..8], .little)) };
                    pos += 8;
                },
                else => return error.InvalidConstantType,
            }
        }

        // Read instructions
        if (pos + 4 > data.len) return error.UnexpectedEof;
        const num_instructions = std.mem.readInt(u32, data[pos..][0..4], .little);
        pos += 4;

        var instructions = try allocator.alloc(Instruction, num_instructions);
        errdefer allocator.free(instructions);

        for (0..num_instructions) |i| {
            if (pos + 5 > data.len) return error.UnexpectedEof;
            instructions[i] = .{
                .op = @enumFromInt(data[pos]),
                .arg = std.mem.readInt(u32, data[pos + 1 ..][0..4], .little),
            };
            pos += 5;
        }

        return .{
            .instructions = instructions,
            .constants = consts,
            .allocator = allocator,
        };
    }
};
