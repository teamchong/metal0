//! Stack frame inspection (AOT: uses Zig debug info)
//!
//! Provides functions to inspect the call stack:
//! - currentframe: Get the current frame's return address
//! - stack: Get stack trace as formatted string
//! - getouterframes: Get caller frames
//! - getinnerframes: Get frames called from this frame (limited in AOT)

const std = @import("std");
const types = @import("types.zig");

pub const FrameInfo = types.FrameInfo;

// ============================================================================
// Stack frame inspection (AOT: uses Zig debug info)
// ============================================================================

/// Get the current frame's return address
/// In AOT compilation, returns the instruction pointer
pub fn currentframe() ?*anyopaque {
    return @returnAddress();
}

/// Get stack trace as formatted string
/// Uses Zig's builtin stack trace functionality
pub fn stack(allocator: std.mem.Allocator) ![]const u8 {
    var buffer = std.ArrayList(u8).init(allocator);
    const writer = buffer.writer();

    var stack_trace = std.builtin.StackTrace{
        .instruction_addresses = undefined,
        .index = 0,
    };

    // Capture current stack
    std.debug.captureStackTrace(@returnAddress(), &stack_trace);

    // Format stack trace
    if (stack_trace.index > 0) {
        try writer.writeAll("Stack (most recent call last):\n");
        var debug_info = std.debug.getSelfDebugInfo() catch {
            try writer.writeAll("  <debug info unavailable>\n");
            return buffer.toOwnedSlice();
        };

        for (stack_trace.instruction_addresses[0..stack_trace.index]) |addr| {
            const symbol = debug_info.getSymbolFromAddress(addr);
            if (symbol.symbol_name) |name| {
                try writer.print("  File \"{s}\", line {d}, in {s}\n", .{
                    symbol.compile_unit_name orelse "<unknown>",
                    symbol.line_info.line orelse 0,
                    name,
                });
            }
        }
    }

    return buffer.toOwnedSlice();
}

/// Get the outer frames (caller frames)
/// Returns frame info for each frame in the call stack
pub fn getouterframes(allocator: std.mem.Allocator, frame: ?*anyopaque, context: usize) ![]FrameInfo {
    _ = frame;
    var frames = std.ArrayList(FrameInfo).init(allocator);

    var stack_trace = std.builtin.StackTrace{
        .instruction_addresses = undefined,
        .index = 0,
    };
    std.debug.captureStackTrace(@returnAddress(), &stack_trace);

    const debug_info = std.debug.getSelfDebugInfo() catch return frames.toOwnedSlice();

    const max_frames = @min(stack_trace.index, context);
    for (stack_trace.instruction_addresses[0..max_frames]) |addr| {
        const symbol = debug_info.getSymbolFromAddress(addr);
        try frames.append(.{
            .filename = symbol.compile_unit_name orelse "<unknown>",
            .lineno = symbol.line_info.line orelse 0,
            .function = symbol.symbol_name orelse "<unknown>",
            .code_context = null,
            .index = null,
        });
    }

    return frames.toOwnedSlice();
}

/// Get the inner frames (frames called from this frame)
/// In AOT, this returns empty as we can only see the call stack up, not down
pub fn getinnerframes(allocator: std.mem.Allocator, _: ?*anyopaque, _: usize) ![]FrameInfo {
    // Inner frames would require tracking frames as they're created
    // In AOT compilation, we only have access to the return address chain
    return allocator.alloc(FrameInfo, 0);
}
