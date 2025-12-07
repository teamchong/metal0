/// emscripten_trampoline_inner - Emscripten Inner Trampoline
/// Mirrors cpython/Python/emscripten_trampoline_inner.c
///
/// Low-level trampoline implementation for Emscripten.
/// Handles the actual stack manipulation and call dispatch.

const std = @import("std");
const builtin = @import("builtin");

// ============================================================================
// Platform Detection
// ============================================================================

/// Check if running on Emscripten/WASM
pub const is_emscripten = builtin.os.tag == .emscripten or builtin.cpu.arch == .wasm32;

// ============================================================================
// Stack Frame Types
// ============================================================================

/// Call frame information
pub const CallFrame = struct {
    /// Return address
    return_addr: usize = 0,
    /// Previous frame pointer
    prev_frame: ?*CallFrame = null,
    /// Saved registers
    saved_regs: [8]usize = [_]usize{0} ** 8,
    /// Local variables area size
    locals_size: usize = 0,
    /// Arguments area
    args: [16]usize = [_]usize{0} ** 16,
    /// Number of arguments
    nargs: usize = 0,
};

/// Stack state for async operations
pub const AsyncStackState = struct {
    /// Saved stack pointer
    sp: usize = 0,
    /// Saved frame pointer
    fp: usize = 0,
    /// Saved call frames
    frames: std.ArrayList(CallFrame),
    /// Is valid
    valid: bool = false,

    pub fn init(allocator: std.mem.Allocator) AsyncStackState {
        return .{
            .frames = std.ArrayList(CallFrame).init(allocator),
        };
    }

    pub fn deinit(self: *AsyncStackState) void {
        self.frames.deinit();
    }

    /// Save current stack state
    pub fn save(self: *AsyncStackState, frame: CallFrame) !void {
        try self.frames.append(frame);
        self.valid = true;
    }

    /// Restore stack state
    pub fn restore(self: *AsyncStackState) ?CallFrame {
        if (!self.valid or self.frames.items.len == 0) {
            return null;
        }
        return self.frames.pop();
    }

    /// Clear state
    pub fn clear(self: *AsyncStackState) void {
        self.frames.clearRetainingCapacity();
        self.valid = false;
    }
};

// ============================================================================
// Trampoline Implementation
// ============================================================================

/// Low-level trampoline context
pub const TrampolineContext = struct {
    const Self = @This();

    /// Current call depth
    depth: u32 = 0,
    /// Maximum call depth
    max_depth: u32 = 1000,
    /// Current frame
    current_frame: ?*CallFrame = null,
    /// Async state
    async_state: ?*AsyncStackState = null,
    /// Error state
    error_state: TrampolineError = .None,

    /// Push a new frame
    pub fn pushFrame(self: *Self, frame: *CallFrame) TrampolineError {
        if (self.depth >= self.max_depth) {
            self.error_state = .StackOverflow;
            return .StackOverflow;
        }

        frame.prev_frame = self.current_frame;
        self.current_frame = frame;
        self.depth += 1;
        return .None;
    }

    /// Pop current frame
    pub fn popFrame(self: *Self) ?*CallFrame {
        const frame = self.current_frame orelse return null;
        self.current_frame = frame.prev_frame;
        if (self.depth > 0) {
            self.depth -= 1;
        }
        return frame;
    }

    /// Get call depth
    pub fn getDepth(self: *const Self) u32 {
        return self.depth;
    }

    /// Check for stack overflow
    pub fn checkOverflow(self: *const Self) bool {
        return self.depth >= self.max_depth;
    }
};

/// Trampoline errors
pub const TrampolineError = enum {
    None,
    StackOverflow,
    InvalidFrame,
    InvalidArguments,
    CallFailed,
    AsyncPending,
};

// ============================================================================
// Call Dispatch
// ============================================================================

/// Dispatch a call through the trampoline
pub fn dispatchCall(
    ctx: *TrampolineContext,
    func: *const fn () callconv(.C) void,
    args: []const usize,
) TrampolineError {
    // Create call frame
    var frame = CallFrame{
        .nargs = @min(args.len, 16),
    };

    // Copy arguments
    for (args[0..frame.nargs], 0..) |arg, i| {
        frame.args[i] = arg;
    }

    // Push frame
    const err = ctx.pushFrame(&frame);
    if (err != .None) {
        return err;
    }

    // Call function
    func();

    // Pop frame
    _ = ctx.popFrame();

    return .None;
}

/// Dispatch a call returning a value
pub fn dispatchCallRet(
    ctx: *TrampolineContext,
    func: *const fn () callconv(.C) usize,
    args: []const usize,
) struct { result: usize, err: TrampolineError } {
    var frame = CallFrame{
        .nargs = @min(args.len, 16),
    };

    for (args[0..frame.nargs], 0..) |arg, i| {
        frame.args[i] = arg;
    }

    const err = ctx.pushFrame(&frame);
    if (err != .None) {
        return .{ .result = 0, .err = err };
    }

    const result = func();

    _ = ctx.popFrame();

    return .{ .result = result, .err = .None };
}

// ============================================================================
// Async Support
// ============================================================================

/// Start an async operation
pub fn asyncStart(ctx: *TrampolineContext, state: *AsyncStackState) TrampolineError {
    if (ctx.current_frame) |frame| {
        state.save(frame.*) catch return .CallFailed;
    }
    ctx.async_state = state;
    return .None;
}

/// Resume from async operation
pub fn asyncResume(ctx: *TrampolineContext) TrampolineError {
    const state = ctx.async_state orelse return .InvalidFrame;

    if (state.restore()) |frame| {
        var new_frame = frame;
        return ctx.pushFrame(&new_frame);
    }

    return .AsyncPending;
}

/// Cancel async operation
pub fn asyncCancel(ctx: *TrampolineContext) void {
    if (ctx.async_state) |state| {
        state.clear();
    }
    ctx.async_state = null;
}

// ============================================================================
// Stack Unwinding
// ============================================================================

/// Unwind stack to a specific depth
pub fn unwindTo(ctx: *TrampolineContext, target_depth: u32) void {
    while (ctx.depth > target_depth) {
        _ = ctx.popFrame();
    }
}

/// Unwind entire stack
pub fn unwindAll(ctx: *TrampolineContext) void {
    while (ctx.popFrame()) |_| {}
}

/// Walk the stack (for debugging)
pub fn walkStack(ctx: *const TrampolineContext, callback: *const fn (*const CallFrame, usize) void) void {
    var frame = ctx.current_frame;
    var idx: usize = 0;

    while (frame) |f| {
        callback(f, idx);
        frame = f.prev_frame;
        idx += 1;
    }
}

// ============================================================================
// Module State
// ============================================================================

var initialized: bool = false;
var global_context: TrampolineContext = .{};

/// Initialize the emscripten_trampoline_inner module
pub fn init() void {
    if (initialized) return;
    initialized = true;
}

/// Get global trampoline context
pub fn getContext() *TrampolineContext {
    return &global_context;
}

/// Reset module state
pub fn reset() void {
    global_context = .{};
    initialized = false;
}

// ============================================================================
// Tests
// ============================================================================

test "call frame" {
    var frame = CallFrame{};
    try std.testing.expectEqual(@as(usize, 0), frame.nargs);
    try std.testing.expect(frame.prev_frame == null);
}

test "trampoline context push pop" {
    var ctx = TrampolineContext{};
    var frame = CallFrame{};

    const err = ctx.pushFrame(&frame);
    try std.testing.expectEqual(TrampolineError.None, err);
    try std.testing.expectEqual(@as(u32, 1), ctx.depth);

    const popped = ctx.popFrame();
    try std.testing.expect(popped != null);
    try std.testing.expectEqual(@as(u32, 0), ctx.depth);
}

test "stack overflow detection" {
    var ctx = TrampolineContext{ .max_depth = 2 };

    var frame1 = CallFrame{};
    var frame2 = CallFrame{};
    var frame3 = CallFrame{};

    _ = ctx.pushFrame(&frame1);
    _ = ctx.pushFrame(&frame2);

    const err = ctx.pushFrame(&frame3);
    try std.testing.expectEqual(TrampolineError.StackOverflow, err);
}

test "unwind to depth" {
    var ctx = TrampolineContext{};
    var frames: [5]CallFrame = undefined;

    for (&frames) |*frame| {
        _ = ctx.pushFrame(frame);
    }

    try std.testing.expectEqual(@as(u32, 5), ctx.depth);

    unwindTo(&ctx, 2);
    try std.testing.expectEqual(@as(u32, 2), ctx.depth);
}

test "unwind all" {
    var ctx = TrampolineContext{};
    var frames: [3]CallFrame = undefined;

    for (&frames) |*frame| {
        _ = ctx.pushFrame(frame);
    }

    unwindAll(&ctx);
    try std.testing.expectEqual(@as(u32, 0), ctx.depth);
}

test "async stack state" {
    const allocator = std.testing.allocator;
    var state = AsyncStackState.init(allocator);
    defer state.deinit();

    const frame = CallFrame{ .nargs = 3 };
    try state.save(frame);

    try std.testing.expect(state.valid);

    const restored = state.restore();
    try std.testing.expect(restored != null);
    try std.testing.expectEqual(@as(usize, 3), restored.?.nargs);
}
