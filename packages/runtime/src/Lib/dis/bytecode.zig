//! Bytecode analysis helper class.
//!
//! Provides methods to analyze and disassemble Python bytecode objects.

const std = @import("std");
const opcode_mod = @import("opcode.zig");
const Opcode = opcode_mod.Opcode;

/// Bytecode analysis helper
pub const Bytecode = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    codeobj: ?*anyopaque,
    first_line: ?u32,
    current_offset: ?usize,

    pub fn init(allocator: std.mem.Allocator, x: anytype) Self {
        _ = x;
        return .{
            .allocator = allocator,
            .codeobj = null,
            .first_line = null,
            .current_offset = null,
        };
    }

    pub fn deinit(self: *Self) void {
        _ = self;
    }

    /// Get info about the code object
    pub fn info(self: *Self) ![]u8 {
        var result: std.ArrayList(u8) = .{};

        // Format code object info similar to CPython's dis.code_info()
        try result.appendSlice(self.allocator, "Name:              ");
        try result.appendSlice(self.allocator, self.co.name);
        try result.append(self.allocator, '\n');

        try result.appendSlice(self.allocator, "Filename:          ");
        try result.appendSlice(self.allocator, self.co.filename);
        try result.append(self.allocator, '\n');

        try result.writer().print("Argument count:    {d}\n", .{self.co.argcount});
        try result.writer().print("Positional-only:   {d}\n", .{self.co.posonlyargcount});
        try result.writer().print("Kw-only arguments: {d}\n", .{self.co.kwonlyargcount});
        try result.writer().print("Number of locals:  {d}\n", .{self.co.nlocals});
        try result.writer().print("Stack size:        {d}\n", .{self.co.stacksize});
        try result.writer().print("Flags:             0x{x}\n", .{self.co.flags});

        if (self.co.varnames.len > 0) {
            try result.appendSlice(self.allocator, "Variable names:\n");
            for (self.co.varnames, 0..) |name, i| {
                try result.writer().print("   {d}: {s}\n", .{ i, name });
            }
        }

        return result.toOwnedSlice(self.allocator);
    }

    /// Disassemble the code
    pub fn dis(self: *Self) ![]u8 {
        var result: std.ArrayList(u8) = .{};

        // Header
        try result.appendSlice(self.allocator, "Disassembly of ");
        try result.appendSlice(self.allocator, self.co.name);
        try result.appendSlice(self.allocator, ":\n");

        // Disassemble each instruction
        var offset: usize = 0;
        while (offset < self.co.code.len) {
            const opcode_byte = self.co.code[offset];
            const opcode: Opcode = @enumFromInt(opcode_byte);

            // Line number marker
            try result.writer().print("{d:>6} ", .{offset});

            // Current instruction marker
            if (self.current_offset != null and offset == self.current_offset.?) {
                try result.appendSlice(self.allocator, "--> ");
            } else {
                try result.appendSlice(self.allocator, "    ");
            }

            // Opcode name
            try result.appendSlice(self.allocator, opcode.name());

            // Argument if present
            if (opcode.hasArg() and offset + 1 < self.co.code.len) {
                const arg = self.co.code[offset + 1];
                try result.writer().print(" {d}", .{arg});

                // Resolve argument if possible
                if (opcode == .LOAD_CONST and arg < self.co.consts.len) {
                    try result.appendSlice(self.allocator, " (");
                    try result.appendSlice(self.allocator, self.co.consts[arg]);
                    try result.append(self.allocator, ')');
                } else if ((opcode == .LOAD_NAME or opcode == .STORE_NAME) and arg < self.co.names.len) {
                    try result.appendSlice(self.allocator, " (");
                    try result.appendSlice(self.allocator, self.co.names[arg]);
                    try result.append(self.allocator, ')');
                } else if ((opcode == .LOAD_FAST or opcode == .STORE_FAST) and arg < self.co.varnames.len) {
                    try result.appendSlice(self.allocator, " (");
                    try result.appendSlice(self.allocator, self.co.varnames[arg]);
                    try result.append(self.allocator, ')');
                }

                offset += 2;
            } else {
                offset += 1;
            }

            try result.append(self.allocator, '\n');
        }

        return result.toOwnedSlice(self.allocator);
    }
};
