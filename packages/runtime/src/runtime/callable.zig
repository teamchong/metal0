const std = @import("std");
const PyValue = @import("../Objects/object.zig").PyValue;

/// Type-erased callable for decorator closures
/// Prevents monomorphization explosion when capturing functions with anytype parameters
pub const AnyCallable = struct {
    /// Opaque pointer to the actual function/closure
    ptr: *const anyopaque,

    /// Function pointer that knows how to call the wrapped function
    /// Takes: (ptr, args, kwargs) -> result
    call_fn: *const fn (*const anyopaque, anytype, anytype) anyerror!PyValue,

    /// Cached __name__ attribute (populated at wrap time)
    __: []const u8,

    /// Wrap any function/closure into a type-erased callable
    pub fn wrap(comptime T: type, func: T) AnyCallable {
        // Generate wrapper functions at compile time for this specific type T
        const Wrapper = struct {
            fn call(ptr: *const anyopaque, args: anytype, kwargs: anytype) anyerror!PyValue {
                const f: *const T = @ptrCast(@alignCast(ptr));
                // Check if T is a closure with .call() method or a direct function
                const type_info = @typeInfo(T);
                if (type_info == .@"struct") {
                    // It's a closure struct - call .call() method
                    return try f.call(args, kwargs);
                } else {
                    // It's a direct function - call it
                    return try f.*(args, kwargs);
                }
            }

            fn getName(ptr: *const anyopaque) []const u8 {
                const f: *const T = @ptrCast(@alignCast(ptr));
                // Check if the type has a __ field (dunder name attribute)
                if (@hasField(T, "__")) {
                    return f.__;
                }
                // Fallback to type name
                return @typeName(T);
            }
        };

        return .{
            .ptr = @ptrCast(&func),
            .call_fn = &Wrapper.call,
            .__ = Wrapper.getName(@ptrCast(&func)),
        };
    }

    /// Call the wrapped function (supports both direct call and .call() method)
    pub fn call(self: AnyCallable, args: anytype, kwargs: anytype) !PyValue {
        return try self.call_fn(self.ptr, args, kwargs);
    }
};
