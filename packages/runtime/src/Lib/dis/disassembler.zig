//! Core disassembly functions.
//!
//! This module provides the main disassembly functions for Python bytecode.

const std = @import("std");
const opcode_mod = @import("opcode.zig");
const Opcode = opcode_mod.Opcode;
const bytecode_mod = @import("bytecode.zig");
const Bytecode = bytecode_mod.Bytecode;
const instruction_mod = @import("instruction.zig");
const Instruction = instruction_mod.Instruction;

/// Disassemble a code object or function and print to file
pub fn dis(allocator: std.mem.Allocator, x: anytype, file: ?std.fs.File, depth: ?i32) !void {
    _ = depth;
    const output_file = file orelse std.io.getStdOut();
    const writer = output_file.writer();

    // Create Bytecode object and get disassembly
    const T = @TypeOf(x);
    if (T == *CodeObject) {
        var bytecode = Bytecode.init(allocator, x);
        defer bytecode.deinit();
        const disasm = try bytecode.dis();
        defer allocator.free(disasm);
        try writer.writeAll(disasm);
    } else if (T == []const u8) {
        // Assume it's raw bytecode
        const disasm = try disassembleBytes(allocator, x, null, null, null, null);
        defer allocator.free(disasm);
        try writer.writeAll(disasm);
    }
}

/// Disassemble a code object to a string
pub fn disassemble(allocator: std.mem.Allocator, co: *CodeObject, lasti: ?i32) ![]u8 {
    var bytecode = Bytecode.init(allocator, co);
    bytecode.current_offset = if (lasti) |l| @intCast(l) else null;
    defer bytecode.deinit();
    return bytecode.dis();
}

/// Disassemble bytecode bytes
pub fn disassembleBytes(allocator: std.mem.Allocator, code: []const u8, lasti: ?i32, varnames: ?[][]const u8, names: ?[][]const u8, constants: anytype) ![]u8 {
    var result: std.ArrayList(u8) = .{};
    errdefer result.deinit(allocator);

    var offset: usize = 0;
    while (offset < code.len) {
        const opcode: Opcode = @enumFromInt(code[offset]);
        var arg: ?u32 = null;

        if (opcode.hasArg() and offset + 1 < code.len) {
            arg = code[offset + 1];
        }

        // Format instruction
        var line_buf: [256]u8 = undefined;
        const line = if (arg) |a|
            std.fmt.bufPrint(&line_buf, "{d:>6} {s:<20} {d}\n", .{ offset, opcode.name(), a }) catch ""
        else
            std.fmt.bufPrint(&line_buf, "{d:>6} {s:<20}\n", .{ offset, opcode.name() }) catch "";

        try result.appendSlice(allocator, line);

        // Handle jump target marker
        if (lasti != null and @as(i32, @intCast(offset)) == lasti.?) {
            // Mark current instruction
        }

        offset += if (opcode.hasArg()) @as(usize, 2) else @as(usize, 1);
    }

    _ = varnames;
    _ = names;
    _ = constants;

    return result.toOwnedSlice(allocator);
}

/// Get instructions from a code object
pub fn getInstructions(allocator: std.mem.Allocator, x: anytype, first_line: ?u32) ![]Instruction {
    _ = allocator;
    _ = x;
    _ = first_line;
    return &[_]Instruction{};
}

/// Show code object info - prints detailed code object information
pub fn showCode(allocator: std.mem.Allocator, co: *CodeObject) ![]u8 {
    var bytecode = Bytecode.init(allocator, co);
    defer bytecode.deinit();
    return bytecode.info();
}

/// Pretty print code object info - alias for showCode
pub fn codeInfo(allocator: std.mem.Allocator, co: *CodeObject) ![]u8 {
    return showCode(allocator, co);
}
