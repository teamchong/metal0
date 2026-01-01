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
                const type_info = @typeInfo(T);

                if (type_info == .@"struct") {
                    // Detect .call() method signature at comptime
                    if (@hasDecl(T, "call")) {
                        const CallFnType = @TypeOf(@field(f.*, "call"));
                        const call_fn_info = @typeInfo(CallFnType);

                        if (call_fn_info == .@"fn") {
                            // Get parameter count (excluding self)
                            const param_count = call_fn_info.@"fn".params.len - 1;

                            return switch (param_count) {
                                0 => try f.call(), // TypedClosure0: .call() takes no args
                                1 => try f.call(args), // TypedClosure1: .call(arg1)
                                else => try f.call(args, kwargs), // TypedClosure2+
                            };
                        }
                    }
                    // Fallback: assume .call(args, kwargs) signature
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

    /// Call the wrapped function with 0 arguments
    pub fn call(self: AnyCallable) !PyValue {
        return try self.call_fn(self.ptr, .{}, .{});
    }

    /// Call the wrapped function with 1 argument
    pub fn call1(self: AnyCallable, arg: anytype) !PyValue {
        return try self.call_fn(self.ptr, arg, .{});
    }

    /// Call the wrapped function with 2 arguments (args and kwargs)
    pub fn call2(self: AnyCallable, args: anytype, kwargs: anytype) !PyValue {
        return try self.call_fn(self.ptr, args, kwargs);
    }
};
