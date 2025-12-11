/// DynamicClosure - Type-erased closure for Python scope semantics
/// Used when a function is defined in multiple if/else branches and used outside

/// DynamicClosure holds a pointer to any closure struct and its call function
pub const DynamicClosure = struct {
    /// Opaque pointer to the actual closure struct
    ptr: *anyopaque,
    /// Type-erased call function that takes (ptr, arg1, arg2) and returns result
    call_fn: *const fn (*anyopaque, anytype, anytype) anyerror!i64,

    const Self = @This();

    /// Create a DynamicClosure from any closure that has a .call() method
    pub fn init(closure: anytype) Self {
        const Closure = @TypeOf(closure);
        return .{
            .ptr = @ptrCast(@constCast(&closure)),
            .call_fn = struct {
                fn callWrapper(ptr: *anyopaque, arg1: anytype, arg2: anytype) anyerror!i64 {
                    const c: *const Closure = @ptrCast(@alignCast(ptr));
                    return c.call(arg1, arg2);
                }
            }.callWrapper,
        };
    }

    /// Call the wrapped closure
    pub fn call(self: Self, arg1: anytype, arg2: anytype) anyerror!i64 {
        return self.call_fn(self.ptr, arg1, arg2);
    }
};
