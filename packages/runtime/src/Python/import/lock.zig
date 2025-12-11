/// import lock - Import lock management
const std = @import("std");
const state = @import("state.zig");

/// Acquire the import lock (reentrant)
pub fn acquireLock() void {
    var st = &(state.import_state orelse return);
    const thread_id = std.Thread.getCurrentId();

    if (st.import_lock_thread == thread_id) {
        st.import_lock_count += 1;
    } else {
        st.import_mutex.lock();
        st.import_lock_thread = thread_id;
        st.import_lock_count = 1;
    }
}

/// Release the import lock
pub fn releaseLock() void {
    var st = &(state.import_state orelse return);

    if (st.import_lock_count > 0) {
        st.import_lock_count -= 1;
        if (st.import_lock_count == 0) {
            st.import_lock_thread = 0;
            st.import_mutex.unlock();
        }
    }
}

/// Check if import lock is held by current thread
pub fn lockHeld() bool {
    const st = state.import_state orelse return false;
    return st.import_lock_count > 0 and
        st.import_lock_thread == std.Thread.getCurrentId();
}
