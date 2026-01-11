const std = @import("std");
pub fn main() !void {
    const T = @TypeOf(main);
    const info = @typeInfo(T);
    try std.io.getStdOut().writer().print("type tag: {s}\n", .{@tagName(info)});
    try std.io.getStdOut().writer().print("type info fields: \n", .{});
    const info_type = @TypeOf(info);
    inline for (std.meta.fields(info_type)) |field| {
        try std.io.getStdOut().writer().print("  {s}\n", .{field.name});
    }
}
