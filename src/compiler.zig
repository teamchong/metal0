const std = @import("std");

/// Compile Zig source code to native binary
pub fn compileZig(allocator: std.mem.Allocator, zig_code: []const u8, output_path: []const u8) !void {
    // Write Zig code to temporary file
    const tmp_path = try std.fmt.allocPrint(allocator, "/tmp/zyth_main_{d}.zig", .{std.time.milliTimestamp()});
    defer allocator.free(tmp_path);

    // Write temp file
    const tmp_file = try std.fs.createFileAbsolute(tmp_path, .{});
    defer tmp_file.close();
    defer std.fs.deleteFileAbsolute(tmp_path) catch {};

    try tmp_file.writeAll(zig_code);

    // Shell out to zig build-exe
    const zig_path = try findZigBinary(allocator);
    defer allocator.free(zig_path);

    const output_flag = try std.fmt.allocPrint(allocator, "-femit-bin={s}", .{output_path});
    defer allocator.free(output_flag);

    const result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{
            zig_path,
            "build-exe",
            tmp_path,
            "-ODebug",
            output_flag,
        },
    });

    if (result.term.Exited != 0) {
        std.debug.print("Zig compilation failed:\n{s}\n", .{result.stderr});
        return error.ZigCompilationFailed;
    }
}

fn findZigBinary(allocator: std.mem.Allocator) ![]const u8 {
    // Try to find zig in PATH
    const result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{ "which", "zig" },
    }) catch {
        // Default to "zig" and hope it's in PATH
        return try allocator.dupe(u8, "zig");
    };

    if (result.term.Exited == 0) {
        const path = std.mem.trim(u8, result.stdout, " \n\r\t");
        return try allocator.dupe(u8, path);
    }

    return try allocator.dupe(u8, "zig");
}
