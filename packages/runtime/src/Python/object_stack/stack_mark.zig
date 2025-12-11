/// stack_mark - Stack mark utilities for exception handling
/// Provides mark/restore functionality for try/except blocks

const ObjectStackMod = @import("ObjectStack.zig");
const ObjectStack = ObjectStackMod.ObjectStack;

/// Stack mark for exception handling
pub const StackMark = struct {
    depth: usize,
    frame_depth: usize,
};

/// Mark current stack position
pub fn markStack(stack: *const ObjectStack) StackMark {
    return .{
        .depth = stack.sp,
        .frame_depth = 0,
    };
}

/// Restore stack to mark
pub fn restoreStack(stack: *ObjectStack, mark: StackMark) void {
    if (stack.sp > mark.depth) {
        @memset(stack.items[mark.depth..stack.sp], null);
        stack.sp = mark.depth;
    }
}
