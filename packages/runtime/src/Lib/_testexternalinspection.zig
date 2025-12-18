//! External Process Inspection Testing Module
//!
//! Test-only module for inspecting external Python processes.
//! Used for testing debugger and profiler functionality.
//!
//! CPython source: Modules/_testexternalinspection.c
//! CPython equivalent: Test module for external process inspection (Linux/macOS only)

const std = @import("std");
const builtin = @import("builtin");

/// Module initialization error
pub const ModuleError = error{
    NotImplemented,
    PlatformNotSupported,
};

/// Whether process_vm_readv is supported (Linux-specific)
/// On non-Linux platforms, this is always false
pub const PROCESS_VM_READV_SUPPORTED: bool = if (builtin.os.tag == .linux) false else false;

/// Get stack trace from external process (stub)
/// Args: (pid: int) -> list of stack frames
/// Raises: NotImplemented
pub fn get_stack_trace(allocator: std.mem.Allocator, pid: i64) ![]const u8 {
    _ = allocator;
    _ = pid;

    // This requires deep integration with process memory inspection APIs:
    // - Linux: process_vm_readv syscall
    // - macOS: task_for_pid + vm_read_overwrite
    // Not implemented yet - tests should be skipped
    return error.NotImplemented;
}

test "_testexternalinspection constants" {
    // PROCESS_VM_READV_SUPPORTED should be false (not implemented)
    try std.testing.expectEqual(false, PROCESS_VM_READV_SUPPORTED);
}
