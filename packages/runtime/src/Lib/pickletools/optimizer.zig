//! Pickle optimization analysis.
//!
//! Analyzes pickle data to identify optimization opportunities.
//! Mirrors: CPython Lib/pickletools.py - optimize function

const std = @import("std");
const types = @import("types.zig");

pub const Opcode = types.Opcode;

/// Generate optimization opportunities report
pub fn optimize(allocator: std.mem.Allocator, pickle: []const u8) ![]u8 {
    var result: std.ArrayList(u8) = .{};
    errdefer result.deinit(allocator);

    var pos: usize = 0;
    var string_count: usize = 0;
    var list_count: usize = 0;
    var dict_count: usize = 0;

    while (pos < pickle.len) {
        const op: Opcode = @enumFromInt(pickle[pos]);
        pos += 1;

        switch (op) {
            .STRING, .SHORT_BINSTRING, .BINSTRING, .UNICODE, .BINUNICODE => {
                string_count += 1;
                // Skip argument
                if (op == .SHORT_BINSTRING or op == .SHORT_BINUNICODE) {
                    if (pos < pickle.len) pos += 1 + pickle[pos];
                } else if (op == .BINSTRING or op == .BINUNICODE) {
                    if (pos + 4 <= pickle.len) {
                        const len = std.mem.readInt(u32, pickle[pos..][0..4], .little);
                        pos += 4 + len;
                    }
                }
            },
            .LIST, .EMPTY_LIST => list_count += 1,
            .DICT, .EMPTY_DICT => dict_count += 1,
            .STOP => break,
            else => {},
        }
    }

    try result.appendSlice(allocator, "Pickle statistics:\n");
    var buf: [256]u8 = undefined;
    const stats = std.fmt.bufPrint(&buf, "  Strings: {d}\n  Lists: {d}\n  Dicts: {d}\n", .{ string_count, list_count, dict_count }) catch "";
    try result.appendSlice(allocator, stats);

    return result.toOwnedSlice(allocator);
}
