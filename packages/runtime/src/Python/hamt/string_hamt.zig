/// String-keyed HAMT convenience helpers
/// Mirrors cpython/Python/hamt.c

const std = @import("std");
const Allocator = std.mem.Allocator;
const core = @import("core.zig");

fn stringHash(s: []const u8) u32 {
    var hash: u32 = 0;
    for (s) |c| {
        hash = hash *% 31 +% c;
    }
    return hash;
}

fn stringEql(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}

/// String-keyed HAMT convenience type
pub fn StringHamt(comptime V: type) type {
    return core.Hamt([]const u8, V);
}

/// Create a new string-keyed HAMT
pub fn newStringHamt(comptime V: type, allocator: Allocator) StringHamt(V) {
    return StringHamt(V).init(allocator, stringHash, stringEql);
}
