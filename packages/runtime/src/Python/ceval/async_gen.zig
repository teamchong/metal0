/// Coroutine and async generator hooks for ceval
/// Mirrors part of cpython/Python/ceval.c

/// Coroutine origin tracking depth
var coroutine_origin_tracking_depth: i32 = 0;

/// Async generator hooks
var async_gen_firstiter: ?*anyopaque = null;
var async_gen_finalizer: ?*anyopaque = null;

/// Set coroutine origin tracking depth
pub fn setCoroutineOriginTrackingDepth(depth: i32) !void {
    if (depth < 0) {
        return error.ValueError;
    }
    coroutine_origin_tracking_depth = depth;
}

/// Get coroutine origin tracking depth
pub fn getCoroutineOriginTrackingDepth() i32 {
    return coroutine_origin_tracking_depth;
}

/// Set async generator first iteration hook
pub fn setAsyncGenFirstiter(firstiter: ?*anyopaque) void {
    async_gen_firstiter = firstiter;
}

/// Get async generator first iteration hook
pub fn getAsyncGenFirstiter() ?*anyopaque {
    return async_gen_firstiter;
}

/// Set async generator finalizer hook
pub fn setAsyncGenFinalizer(finalizer: ?*anyopaque) void {
    async_gen_finalizer = finalizer;
}

/// Get async generator finalizer hook
pub fn getAsyncGenFinalizer() ?*anyopaque {
    return async_gen_finalizer;
}
