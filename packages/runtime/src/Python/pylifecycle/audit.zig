/// pylifecycle audit hooks
const state = @import("state.zig");
const types = @import("types.zig");
const AuditHook = types.AuditHook;

/// Add an audit hook
pub fn addAuditHook(hook: *AuditHook) i32 {
    hook.next = state.runtime.audit_hooks.head;
    state.runtime.audit_hooks.head = hook;
    state.runtime.audit_hooks.count += 1;
    return 0;
}

/// Trigger an audit event
pub fn audit(event: []const u8, args: ?*anyopaque) void {
    var hook = state.runtime.audit_hooks.head;
    while (hook) |h| {
        h.func(event, args);
        hook = h.next;
    }
}
