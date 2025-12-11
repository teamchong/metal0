//! Main entry points and module functions for the Python debugger
//!
//! Provides convenience functions like set_trace(), pm(), run(), runscript().

const std = @import("std");
const allocator_helper = @import("utils.allocator_helper");
const pdb_mod = @import("pdb.zig");
const Pdb = pdb_mod.Pdb;
const types = @import("types.zig");
const Frame = types.Frame;

// Global debugger instance (thread-local for safety)
threadlocal var global_pdb: ?*Pdb = null;

/// Convenience function to set a breakpoint at the call site
/// Usage: pdb.set_trace()
pub fn set_trace() void {
    // In AOT mode, this is a no-op at runtime
    // The compiled code should check for breakpoints
    // This is a marker for developers to know debugging should start here
    if (global_pdb) |pdb| {
        pdb.setTrace();
    }
}

/// Post-mortem debugging of last exception
/// Usage: pdb.pm()
pub fn pm() void {
    if (global_pdb) |pdb| {
        pdb.postMortem() catch {};
    }
}

/// Run a statement under the debugger
/// Usage: pdb.run(statement, globals, locals)
pub fn run(statement: []const u8, globals: ?*anyopaque, locals: ?*anyopaque) void {
    _ = globals;
    _ = locals;
    // Use heap allocator since we don't have access to one
    const allocator = allocator_helper.fast_allocator;
    var pdb = Pdb.init(allocator, null);
    defer pdb.deinit();
    global_pdb = &pdb;
    defer {
        global_pdb = null;
    }
    pdb.run(statement) catch {};
}

/// Run a script file under the debugger
/// Usage: pdb.runscript(filename)
pub fn runscript(allocator: std.mem.Allocator, filename: []const u8) !void {
    var pdb = Pdb.init(allocator, null);
    defer pdb.deinit();
    global_pdb = &pdb;
    defer {
        global_pdb = null;
    }

    // Create frame for the script
    var frame = Frame.init(allocator, filename, 1, "<module>");
    try pdb.stack.append(frame);
    pdb.curindex = 0;
    pdb.curframe = &pdb.stack.items[0];

    try pdb.message("Debugging script:");
    try pdb.stdout.print("> {s}\n", .{filename});

    // Enter interactive mode
    try pdb.interact();
}
