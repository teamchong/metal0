/// object_stack - Object Stack for Evaluation
/// Mirrors cpython/Python/object_stack.c
///
/// This module provides a stack for Python objects during evaluation:
/// - Push/pop operations for bytecode execution
/// - Stack frame management
/// - Overflow/underflow detection
/// - Integration with garbage collection
///
/// Modular structure:
/// - ObjectStack.zig - Main stack implementation
/// - ChunkedObjectStack.zig - Chunked stack for large stacks
/// - stack_mark.zig - Stack mark utilities for exception handling
/// - tests.zig - Test suite

// Re-export main types and functions
pub const ObjectStack = @import("object_stack/ObjectStack.zig").ObjectStack;
pub const PyObjectRef = @import("object_stack/ObjectStack.zig").PyObjectRef;
pub const NULL_REF = @import("object_stack/ObjectStack.zig").NULL_REF;
pub const DEFAULT_STACK_SIZE = @import("object_stack/ObjectStack.zig").DEFAULT_STACK_SIZE;
pub const MAX_STACK_SIZE = @import("object_stack/ObjectStack.zig").MAX_STACK_SIZE;

pub const ChunkedObjectStack = @import("object_stack/ChunkedObjectStack.zig").ChunkedObjectStack;

pub const StackMark = @import("object_stack/stack_mark.zig").StackMark;
pub const markStack = @import("object_stack/stack_mark.zig").markStack;
pub const restoreStack = @import("object_stack/stack_mark.zig").restoreStack;

// Initialization
pub fn init() void {}

// Tests
test {
    _ = @import("object_stack/tests.zig");
}
