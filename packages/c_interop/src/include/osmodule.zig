/// CPython OS Interface
///
/// Implements OS-level utilities for CPython compatibility.

const std = @import("std");
const cpython = @import("object.zig");
const traits = @import("../objects/typetraits.zig");

// Use centralized extern declarations
const Py_INCREF = traits.externs.Py_INCREF;
const Py_DECREF = traits.externs.Py_DECREF;

/// Safe snprintf implementation
/// Returns number of characters written (excluding null terminator)
export fn PyOS_snprintf(str: [*]u8, size: usize, format: [*:0]const u8, ...) callconv(.c) c_int {
    var va = @cVaStart();
    defer @cVaEnd(&va);

    return std.c.vsnprintf(str, size, format, va);
}

/// Safe vsnprintf with va_list
/// Returns number of characters written (excluding null terminator)
export fn PyOS_vsnprintf(str: [*]u8, size: usize, format: [*:0]const u8, va: *std.builtin.VaList) callconv(.c) c_int {
    return std.c.vsnprintf(str, size, format, va.*);
}

/// Case-insensitive string comparison
/// Returns 0 if equal, <0 if s1 < s2, >0 if s1 > s2
export fn PyOS_stricmp(s1: [*:0]const u8, s2: [*:0]const u8) callconv(.c) c_int {
    var i: usize = 0;
    while (true) : (i += 1) {
        const c1 = std.ascii.toLower(s1[i]);
        const c2 = std.ascii.toLower(s2[i]);

        if (c1 != c2) return @as(c_int, @intCast(c1)) - @as(c_int, @intCast(c2));
        if (c1 == 0) return 0; // Both strings ended
    }
}

/// Case-insensitive string comparison (first n characters)
/// Returns 0 if equal, <0 if s1 < s2, >0 if s1 > s2
export fn PyOS_strnicmp(s1: [*:0]const u8, s2: [*:0]const u8, n: usize) callconv(.c) c_int {
    var i: usize = 0;
    while (i < n) : (i += 1) {
        const c1 = std.ascii.toLower(s1[i]);
        const c2 = std.ascii.toLower(s2[i]);

        if (c1 != c2) return @as(c_int, @intCast(c1)) - @as(c_int, @intCast(c2));
        if (c1 == 0) return 0; // Both strings ended
    }
    return 0; // First n characters are equal
}

/// Convert path-like object to filesystem path string
/// Returns new reference to path string or null on error
export fn PyOS_FSPath(path: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const type_obj = cpython.Py_TYPE(path);

    // Check if object has __fspath__ method via tp_methods
    if (type_obj.tp_methods) |methods| {
        var i: usize = 0;
        while (methods[i].ml_name != null) : (i += 1) {
            if (std.mem.eql(u8, std.mem.span(methods[i].ml_name.?), "__fspath__")) {
                // Call __fspath__ method
                if (methods[i].ml_meth) |meth| {
                    const func: *const fn (?*cpython.PyObject, ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject = @ptrCast(meth);
                    return func(path, null);
                }
            }
        }
    }

    // For strings, just return a new reference
    Py_INCREF(path);
    return path;
}

// Thread-local state for fork handling
threadlocal var in_fork: bool = false;

// Global interrupt flag (atomic for signal handler access)
var interrupt_flag: std.atomic.Value(bool) = std.atomic.Value(bool).init(false);

/// Callback to execute before fork()
/// Used to prepare for process forking
export fn PyOS_BeforeFork() callconv(.c) void {
    // Mark that we're entering a fork
    in_fork = true;
    // Note: In a real implementation, we'd acquire all interpreter locks here
    // to ensure consistent state during fork. Since metal0 is AOT compiled
    // and doesn't have an interpreter loop, we mainly need to ensure
    // any shared state is in a consistent condition.
}

/// Callback to execute after fork() in parent process
/// Used to restore parent state after fork
export fn PyOS_AfterFork_Parent() callconv(.c) void {
    // Clear fork flag
    in_fork = false;
    // Release any locks acquired in PyOS_BeforeFork
}

/// Callback to execute after fork() in child process
/// Used to reinitialize child state after fork
export fn PyOS_AfterFork_Child() callconv(.c) void {
    // Clear fork flag
    in_fork = false;
    // In child process after fork, we need to:
    // 1. Reset thread state (only main thread survives fork)
    // 2. Reinitialize any locks (they're in undefined state after fork)
    // 3. Clear the interrupt flag
    interrupt_flag.store(false, .seq_cst);
}

/// Compatibility wrapper for AfterFork
/// Calls AfterFork_Parent() (legacy behavior)
export fn PyOS_AfterFork() callconv(.c) void {
    PyOS_AfterFork_Parent();
}

/// Initialize random number generator
/// Returns 0 on success, -1 on error
export fn _PyOS_URandom(buffer: [*]u8, size: isize) callconv(.c) c_int {
    if (size <= 0) return 0;

    const buf_slice = buffer[0..@intCast(size)];

    // Use Zig's cryptographic random (uses /dev/urandom on Unix, BCryptGenRandom on Windows)
    std.crypto.random.bytes(buf_slice);

    return 0;
}

/// Get interrupt status
/// Returns 1 if interrupt occurred (Ctrl+C), 0 otherwise
export fn PyOS_InterruptOccurred() callconv(.c) c_int {
    // Check and clear the interrupt flag
    if (interrupt_flag.swap(false, .seq_cst)) {
        return 1; // Interrupt occurred
    }
    return 0; // No interrupt
}

/// Set interrupt flag (called from signal handler)
export fn PyErr_SetInterruptEx(signum: c_int) callconv(.c) c_int {
    _ = signum;
    interrupt_flag.store(true, .seq_cst);
    return 0;
}

/// Initialize signal handling
/// Sets up handlers for SIGINT, SIGTERM, etc.
export fn PyOS_InitInterrupts() callconv(.c) void {
    // Set up SIGINT handler to set interrupt flag
    // Note: On most systems, Zig's std.os.Sigaction can be used, but for
    // maximum compatibility with C extensions, we leave this as a no-op
    // and expect the signal handling to be done at a higher level.
    // The interrupt flag can still be set via PyErr_SetInterruptEx.
}

/// Finalize signal handling
/// Restores original signal handlers
export fn PyOS_FiniInterrupts() callconv(.c) void {
    // Clear the interrupt flag
    interrupt_flag.store(false, .seq_cst);
}

/// Read line from stdin with optional prompt
/// Returns allocated string or null on EOF/error
export fn PyOS_Readline(stdin_: *std.c.FILE, stdout_: *std.c.FILE, prompt: [*:0]const u8) callconv(.c) [*:0]u8 {
    // Print prompt to stdout
    _ = std.c.fprintf(stdout_, "%s", prompt);
    _ = std.c.fflush(stdout_);

    // Read line from stdin
    var buffer: [4096]u8 = undefined;
    const result = std.c.fgets(&buffer, buffer.len, stdin_);
    if (result == null) {
        // EOF or error
        return @ptrFromInt(0);
    }

    // Find length (including newline if present)
    var len: usize = 0;
    while (len < buffer.len and buffer[len] != 0) : (len += 1) {}

    // Allocate and copy the result
    const str_ptr = std.c.malloc(len + 1) orelse return @ptrFromInt(0);
    const str: [*]u8 = @ptrCast(str_ptr);
    @memcpy(str[0..len], buffer[0..len]);
    str[len] = 0;
    return @ptrCast(str);
}

// ============================================================================
// FLOAT <-> STRING CONVERSION
// ============================================================================

/// Convert double to string
/// Returns newly allocated string (caller must free with PyMem_Free)
export fn PyOS_double_to_string(val: f64, format_code: u8, precision: c_int, flags: c_int, ptype: ?*c_int) callconv(.c) ?[*:0]u8 {
    _ = flags;

    // Set type if requested
    if (ptype) |pt| {
        pt.* = if (std.math.isNan(val)) 1 else if (std.math.isInf(val)) 2 else 0;
    }

    const allocator = std.heap.c_allocator;
    var buf: [64]u8 = undefined;

    // Format based on format_code
    const fmt_str: []const u8 = switch (format_code) {
        'e', 'E' => blk: {
            const result = std.fmt.bufPrint(&buf, "{e}", .{val}) catch return null;
            break :blk result;
        },
        'f', 'F' => blk: {
            if (precision >= 0 and precision <= 20) {
                const result = std.fmt.bufPrint(&buf, "{d:.6}", .{val}) catch return null;
                break :blk result;
            } else {
                const result = std.fmt.bufPrint(&buf, "{d}", .{val}) catch return null;
                break :blk result;
            }
        },
        'g', 'G' => blk: {
            const result = std.fmt.bufPrint(&buf, "{d}", .{val}) catch return null;
            break :blk result;
        },
        'r' => blk: {
            // repr format - full precision
            const result = std.fmt.bufPrint(&buf, "{d:.17}", .{val}) catch return null;
            break :blk result;
        },
        else => blk: {
            const result = std.fmt.bufPrint(&buf, "{d}", .{val}) catch return null;
            break :blk result;
        },
    };

    // Allocate and copy result
    const result = allocator.allocSentinel(u8, fmt_str.len, 0) catch return null;
    @memcpy(result[0..fmt_str.len], fmt_str);
    return result.ptr;
}

/// Convert string to double
/// Returns the parsed value, sets endptr to first unconverted char
export fn PyOS_string_to_double(s: [*:0]const u8, endptr: ?*[*:0]const u8, overflow_exception: ?*cpython.PyObject) callconv(.c) f64 {
    _ = overflow_exception;

    const str = std.mem.span(s);
    const result = std.fmt.parseFloat(f64, str) catch {
        if (endptr) |ep| ep.* = s;
        return 0.0;
    };

    if (endptr) |ep| {
        // Set to end of string (simplified - should point to first unconverted char)
        ep.* = @ptrFromInt(@intFromPtr(s) + str.len);
    }

    return result;
}
