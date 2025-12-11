//! Pickle disassembler for human-readable analysis.
//!
//! Provides dis() function to disassemble pickle data with annotations.
//! Mirrors: CPython Lib/pickletools.py - dis function

const std = @import("std");
const types = @import("types.zig");

pub const Opcode = types.Opcode;

/// Disassemble pickle data
pub fn dis(allocator: std.mem.Allocator, pickle: []const u8, file: ?std.fs.File, memo: ?*anyopaque, indentlevel: usize, annotate: bool) !void {
    _ = memo;
    _ = allocator;

    const writer = if (file) |f| f.writer() else std.io.getStdOut().writer();
    const indent = " " ** 4;
    _ = indent;

    var pos: usize = 0;
    var proto: u8 = 0;

    while (pos < pickle.len) {
        const op_byte = pickle[pos];
        const opcode: Opcode = @enumFromInt(op_byte);
        const op_name = opcode.name();

        // Print position
        var buf: [64]u8 = undefined;
        const pos_str = std.fmt.bufPrint(&buf, "{d: >5}: ", .{pos}) catch "";
        try writer.writeAll(pos_str);

        // Print indentation
        for (0..indentlevel) |_| {
            try writer.writeAll("    ");
        }

        // Print opcode name
        try writer.writeAll(op_name);

        // Parse and print argument
        pos += 1;
        var arg: ?[]const u8 = null;

        switch (opcode) {
            .PROTO => {
                if (pos < pickle.len) {
                    proto = pickle[pos];
                    const arg_str = std.fmt.bufPrint(&buf, " {d}", .{proto}) catch "";
                    try writer.writeAll(arg_str);
                    pos += 1;
                }
            },
            .BININT => {
                if (pos + 4 <= pickle.len) {
                    const val = std.mem.readInt(i32, pickle[pos..][0..4], .little);
                    const arg_str = std.fmt.bufPrint(&buf, " {d}", .{val}) catch "";
                    try writer.writeAll(arg_str);
                    pos += 4;
                }
            },
            .BININT1 => {
                if (pos < pickle.len) {
                    const arg_str = std.fmt.bufPrint(&buf, " {d}", .{pickle[pos]}) catch "";
                    try writer.writeAll(arg_str);
                    pos += 1;
                }
            },
            .BININT2 => {
                if (pos + 2 <= pickle.len) {
                    const val = std.mem.readInt(u16, pickle[pos..][0..2], .little);
                    const arg_str = std.fmt.bufPrint(&buf, " {d}", .{val}) catch "";
                    try writer.writeAll(arg_str);
                    pos += 2;
                }
            },
            .BINFLOAT => {
                if (pos + 8 <= pickle.len) {
                    const val = @as(f64, @bitCast(std.mem.readInt(u64, pickle[pos..][0..8], .big)));
                    const arg_str = std.fmt.bufPrint(&buf, " {d}", .{val}) catch "";
                    try writer.writeAll(arg_str);
                    pos += 8;
                }
            },
            .SHORT_BINSTRING, .SHORT_BINBYTES, .SHORT_BINUNICODE => {
                if (pos < pickle.len) {
                    const length = pickle[pos];
                    pos += 1;
                    if (pos + length <= pickle.len) {
                        arg = pickle[pos .. pos + length];
                        try writer.writeAll(" '");
                        try writer.writeAll(arg.?);
                        try writer.writeAll("'");
                        pos += length;
                    }
                }
            },
            .BINSTRING, .BINUNICODE, .BINBYTES => {
                if (pos + 4 <= pickle.len) {
                    const length = std.mem.readInt(u32, pickle[pos..][0..4], .little);
                    pos += 4;
                    if (pos + length <= pickle.len) {
                        arg = pickle[pos .. pos + length];
                        try writer.writeAll(" '");
                        if (arg.?.len <= 40) {
                            try writer.writeAll(arg.?);
                        } else {
                            try writer.writeAll(arg.?[0..40]);
                            try writer.writeAll("...");
                        }
                        try writer.writeAll("'");
                        pos += length;
                    }
                }
            },
            .BINGET, .BINPUT => {
                if (pos < pickle.len) {
                    const arg_str = std.fmt.bufPrint(&buf, " {d}", .{pickle[pos]}) catch "";
                    try writer.writeAll(arg_str);
                    pos += 1;
                }
            },
            .LONG_BINGET, .LONG_BINPUT => {
                if (pos + 4 <= pickle.len) {
                    const val = std.mem.readInt(u32, pickle[pos..][0..4], .little);
                    const arg_str = std.fmt.bufPrint(&buf, " {d}", .{val}) catch "";
                    try writer.writeAll(arg_str);
                    pos += 4;
                }
            },
            else => {},
        }

        // Print annotation
        if (annotate) {
            try writer.writeAll("  # ");
            try writer.writeAll(opcode.doc());
        }

        try writer.writeAll("\n");

        if (opcode == .STOP) break;
    }
}
