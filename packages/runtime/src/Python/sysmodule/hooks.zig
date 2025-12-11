/// hooks - Tracing, Profiling, and Audit Hooks
/// Debug and monitoring hooks for the runtime

const std = @import("std");

// ============================================================================
// Function Types
// ============================================================================

/// Profile function type
pub const ProfileFunc = *const fn (frame: anytype, event: []const u8, arg: anytype) void;

/// Trace function type
pub const TraceFunc = *const fn (frame: anytype, event: []const u8, arg: anytype) void;

/// Audit hook type
pub const AuditHook = *const fn (event: []const u8, args: anytype) void;

// ============================================================================
// Profile and Trace Hooks
// ============================================================================

/// Current profile function (null = disabled)
var profile_func: ?ProfileFunc = null;

/// Current trace function (null = disabled)
var trace_func: ?TraceFunc = null;

/// Set the profile function
/// Mirrors: sys.setprofile()
pub fn setprofile(func: ?ProfileFunc) void {
    profile_func = func;
}

/// Get the profile function
/// Mirrors: sys.getprofile()
pub fn getprofile() ?ProfileFunc {
    return profile_func;
}

/// Set the trace function
/// Mirrors: sys.settrace()
pub fn settrace(func: ?TraceFunc) void {
    trace_func = func;
}

/// Get the trace function
/// Mirrors: sys.gettrace()
pub fn gettrace() ?TraceFunc {
    return trace_func;
}

// ============================================================================
// Audit Hooks
// ============================================================================

/// Registered audit hooks
var audit_hooks: [16]?AuditHook = [_]?AuditHook{null} ** 16;
var audit_hook_count: usize = 0;

/// Add an audit hook
/// Mirrors: sys.addaudithook()
pub fn addaudithook(hook: AuditHook) !void {
    if (audit_hook_count >= audit_hooks.len) {
        return error.TooManyAuditHooks;
    }
    audit_hooks[audit_hook_count] = hook;
    audit_hook_count += 1;
}

/// Trigger audit event
pub fn audit(event: []const u8, args: anytype) void {
    for (audit_hooks[0..audit_hook_count]) |maybe_hook| {
        if (maybe_hook) |hook| {
            hook(event, args);
        }
    }
}
