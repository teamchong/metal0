/// Compile Python source via metal0 subprocess (for dynamic eval)
/// Spawns: metal0 --emit-bytecode <source>
/// Returns parsed BytecodeProgram from subprocess stdout
const std = @import("std");
const bytecode = @import("../compile.zig");

pub fn compileViaSubprocess(allocator: std.mem.Allocator, source: []const u8) !bytecode.BytecodeProgram {
    // Build argv: ["metal0", "--emit-bytecode", source]
    const argv = [_][]const u8{ "metal0", "--emit-bytecode", source };

    // Spawn subprocess
    var child = std.process.Child.init(&argv, allocator);
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Pipe;

    try child.spawn();

    // Read stdout (bytecode binary)
    const stdout = child.stdout orelse return error.NoStdout;
    const bytecode_data = try stdout.readToEndAlloc(allocator, 1024 * 1024); // 1MB max
    defer allocator.free(bytecode_data);

    // Wait for child
    const term = try child.wait();
    switch (term) {
        .Exited => |code| if (code != 0) return error.SubprocessFailed,
        else => return error.SubprocessFailed,
    }

    // Parse bytecode
    return bytecode.BytecodeProgram.deserialize(allocator, bytecode_data);
}
