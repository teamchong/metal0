const std = @import("std");
const ascii = std.ascii;

pub fn main() !void {
    std.debug.print("Zig ascii.isWhitespace matches:\n", .{});
    var i: u16 = 0;
    while (i < 256) : (i += 1) {
        const c: u8 = @intCast(i);
        if (ascii.isWhitespace(c)) {
            std.debug.print("  {d:3} '{c}'\n", .{c, if (c >= 32 and c < 127) c else '?'});
        }
    }
    
    std.debug.print("\nZig ascii.isAlphanumeric + _ count:\n", .{});
    var count: usize = 0;
    i = 0;
    while (i < 256) : (i += 1) {
        const c: u8 = @intCast(i);
        if (ascii.isAlphanumeric(c) or c == '_') {
            count += 1;
        }
    }
    std.debug.print("  Total: {d}\n", .{count});
}
