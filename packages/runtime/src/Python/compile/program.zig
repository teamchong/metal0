/// Compiled bytecode program with serialization support
const std = @import("std");
const constants = @import("constants.zig");
const Instruction = constants.Instruction;
const Constant = constants.Constant;
const OpCode = constants.OpCode;

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
    /// Supports both "PYBC" (old format) and "MET0" (compiler format)
    pub fn deserialize(allocator: std.mem.Allocator, data: []const u8) !BytecodeProgram {
        if (data.len < 10) return error.InvalidBytecode;

        // Check magic - support both formats
        if (std.mem.eql(u8, data[0..4], "MET0")) {
            return deserializeMET0(allocator, data);
        }

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

    /// Deserialize MET0 format bytecode (from metal0 compiler)
    /// Format: [magic:4][version:2][bytecode_len:4][bytecode][constants_len:4]
    /// Translates new bytecode opcodes to old VM opcodes
    fn deserializeMET0(allocator: std.mem.Allocator, data: []const u8) !BytecodeProgram {
        if (data.len < 14) return error.InvalidBytecode; // MET0 + version(2) + len(4) + consts_len(4)

        var pos: usize = 4; // Skip "MET0" magic

        // Version (u16)
        const version = std.mem.readInt(u16, data[pos..][0..2], .little);
        _ = version; // Version check could be added later
        pos += 2;

        // Bytecode length
        const bytecode_len = std.mem.readInt(u32, data[pos..][0..4], .little);
        pos += 4;

        if (pos + bytecode_len > data.len) return error.UnexpectedEof;
        const bytecode_bytes = data[pos..][0..bytecode_len];
        pos += bytecode_len;

        // Constants count (constants not serialized in MET0 format currently)
        if (pos + 4 > data.len) return error.UnexpectedEof;
        const num_constants = std.mem.readInt(u32, data[pos..][0..4], .little);
        _ = num_constants;

        // Parse the raw bytecode into instructions
        // MET0 bytecode uses varint encoding for arguments
        var instructions_list: std.ArrayList(Instruction) = .{};
        errdefer instructions_list.deinit(allocator);

        // Collect constants for LOAD_I8/LOAD_I16/etc instructions
        var constants_list: std.ArrayList(Constant) = .{};
        errdefer constants_list.deinit(allocator);

        var bc_pos: usize = 0;
        while (bc_pos < bytecode_bytes.len) {
            const op_byte = bytecode_bytes[bc_pos];
            bc_pos += 1;

            // Read single-byte argument if needed (NOT varint - AST compiler uses u8 args)
            var arg: u32 = 0;

            // Check if instruction has an argument by looking at opcode
            const has_arg = switch (op_byte) {
                // Stack ops without args
                0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06 => false,
                // Constant loads with no arg (LOAD_NONE, LOAD_TRUE, LOAD_FALSE, LOAD_ZERO, LOAD_ONE)
                0x11, 0x12, 0x13, 0x17, 0x18 => false,
                // Binary ops without args
                0x40, 0x41, 0x42, 0x43, 0x44, 0x45, 0x46, 0x47, 0x48, 0x49, 0x4A, 0x4B, 0x4C, 0x4D => false,
                // Unary ops without args
                0x50, 0x51, 0x52, 0x53, 0x54 => false,
                // Compare ops without args
                0x60, 0x61, 0x62, 0x63, 0x64, 0x65, 0x66, 0x67, 0x68, 0x69 => false,
                // Return without arg
                0x88, 0x89 => false,
                // Optimized locals without arg
                0x23, 0x24, 0x25, 0x26, 0x27, 0x28, 0x29, 0x2A => false,
                // Optimized calls without arg
                0x81, 0x82, 0x83, 0x84 => false,
                // Everything else has a single-byte arg
                else => true,
            };

            if (has_arg and bc_pos < bytecode_bytes.len) {
                // Single byte arg (matches emitArg in ast_compiler.zig)
                arg = bytecode_bytes[bc_pos];
                bc_pos += 1;
            }

            // Translate new bytecode opcodes to old VM opcodes
            // New bytecode:  LOAD_I8=0x14, ADD=0x40, DIV=0x43, RETURN=0x88
            // Old VM: LoadConst=0, Add=2, Div=5, Return=18
            const translated_op: OpCode = switch (op_byte) {
                // LOAD_I8: Create constant and emit LoadConst
                0x14 => blk: {
                    const const_idx = constants_list.items.len;
                    try constants_list.append(allocator, .{ .int = @as(i64, @intCast(arg)) });
                    arg = @intCast(const_idx);
                    break :blk .LoadConst;
                },
                // LOAD_NONE: Create None constant
                0x11 => blk: {
                    const const_idx = constants_list.items.len;
                    try constants_list.append(allocator, .{ .none = {} });
                    arg = @intCast(const_idx);
                    break :blk .LoadConst;
                },
                // LOAD_TRUE: Create True constant
                0x12 => blk: {
                    const const_idx = constants_list.items.len;
                    try constants_list.append(allocator, .{ .bool = true });
                    arg = @intCast(const_idx);
                    break :blk .LoadConst;
                },
                // LOAD_FALSE: Create False constant
                0x13 => blk: {
                    const const_idx = constants_list.items.len;
                    try constants_list.append(allocator, .{ .bool = false });
                    arg = @intCast(const_idx);
                    break :blk .LoadConst;
                },
                // LOAD_ZERO, LOAD_ONE: Create constant 0 or 1
                0x17 => blk: {
                    const const_idx = constants_list.items.len;
                    try constants_list.append(allocator, .{ .int = 0 });
                    arg = @intCast(const_idx);
                    break :blk .LoadConst;
                },
                0x18 => blk: {
                    const const_idx = constants_list.items.len;
                    try constants_list.append(allocator, .{ .int = 1 });
                    arg = @intCast(const_idx);
                    break :blk .LoadConst;
                },
                // LOAD_CONST
                0x10 => .LoadConst,
                // POP
                0x01 => .Pop,
                // Binary ops: ADD=0x40, SUB=0x41, MUL=0x42, DIV=0x43, FLOORDIV=0x44, MOD=0x45, POW=0x46
                0x40 => .Add,
                0x41 => .Sub,
                0x42 => .Mult,
                0x43 => .Div,
                0x44 => .FloorDiv,
                0x45 => .Mod,
                0x46 => .Pow,
                // Unary ops: NEG=0x50, POS=0x51, NOT=0x52, INVERT=0x53
                0x50 => .USub,   // NEG: unary minus -x
                0x51 => .UAdd,   // POS: unary plus +x
                0x52 => .Not,    // NOT: boolean not
                0x53 => .Invert, // INVERT: bitwise ~
                // Compare ops: LT=0x60, LE=0x61, EQ=0x62, NE=0x63, GT=0x64, GE=0x65
                0x60 => .Lt,
                0x61 => .LtE,
                0x62 => .Eq,
                0x63 => .NotEq,
                0x64 => .Gt,
                0x65 => .GtE,
                // RETURN=0x88
                0x88 => .Return,
                // Unknown - skip
                else => continue,
            };

            try instructions_list.append(allocator, .{
                .op = translated_op,
                .arg = arg,
            });
        }

        const instructions = try instructions_list.toOwnedSlice(allocator);
        const consts = try constants_list.toOwnedSlice(allocator);

        // Build result struct
        const result: BytecodeProgram = .{
            .instructions = instructions,
            .constants = consts,
            .allocator = allocator,
        };

        // Verify result is sane before returning
        if (@intFromPtr(result.instructions.ptr) == 0 or result.instructions.len > 10000) {
            @panic("deserializeMET0: corrupted instructions before return");
        }
        if (@intFromPtr(result.constants.ptr) == 0 and result.constants.len > 0) {
            @panic("deserializeMET0: corrupted constants before return");
        }

        return result;
    }
};
