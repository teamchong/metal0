/// Generic closure implementation (comptime configurable)
///
/// Pattern: Write once, specialize many!
/// - Closures with any number of captures
/// - Closures with any argument types
/// - Zero abstraction cost (comptime specialization)
const std = @import("std");

/// Configuration for closure behavior (unused - kept for reference)
pub const ClosureConfig = struct {
    /// Tuple type for captured variables
    CaptureType: type,

    /// Tuple type for function arguments
    ArgType: type,

    /// Return type
    ReturnType: type,
};

/// Generic closure implementation
///
/// Creates a closure that:
/// 1. Stores captured variables in a struct
/// 2. Provides a .call() method that passes captures + args to callFn
/// 3. Zero runtime overhead (everything resolved at comptime)
///
/// Example:
///   const MyClosure = ClosureImpl(.{
///       .CaptureType = struct { x: i64 },
///       .ArgType = struct { y: i64 },
///       .ReturnType = i64,
///       .callFn = myFunction,
///   });
pub fn ClosureImpl(comptime config: ClosureConfig) type {
    return struct {
        const Self = @This();

        captures: config.CaptureType,

        /// Call the closure with arguments
        pub fn call(self: Self, args: config.ArgType) config.ReturnType {
            return config.callFn(self.captures, args);
        }
    };
}

/// Helper to create a closure with no arguments (captures only)
pub fn Closure0(comptime CaptureT: type, comptime RetT: type, comptime func: fn (CaptureT) RetT) type {
    return struct {
        const Self = @This();
        captures: CaptureT,

        pub fn call(self: Self) RetT {
            return func(self.captures);
        }
    };
}

/// Helper to create a closure with single argument
pub fn Closure1(comptime CaptureT: type, comptime ArgT: type, comptime RetT: type, comptime func: fn (CaptureT, ArgT) RetT) type {
    return struct {
        const Self = @This();
        captures: CaptureT,

        pub fn call(self: Self, arg: ArgT) RetT {
            return func(self.captures, arg);
        }
    };
}

/// Helper to create a closure with two arguments
pub fn Closure2(comptime CaptureT: type, comptime Arg1T: type, comptime Arg2T: type, comptime RetT: type, comptime func: fn (CaptureT, Arg1T, Arg2T) RetT) type {
    return struct {
        const Self = @This();
        captures: CaptureT,

        pub fn call(self: Self, arg1: Arg1T, arg2: Arg2T) RetT {
            return func(self.captures, arg1, arg2);
        }
    };
}

/// Helper to create a closure with three arguments
pub fn Closure3(comptime CaptureT: type, comptime Arg1T: type, comptime Arg2T: type, comptime Arg3T: type, comptime RetT: type, comptime func: fn (CaptureT, Arg1T, Arg2T, Arg3T) RetT) type {
    return struct {
        const Self = @This();
        captures: CaptureT,

        pub fn call(self: Self, arg1: Arg1T, arg2: Arg2T, arg3: Arg3T) RetT {
            return func(self.captures, arg1, arg2, arg3);
        }
    };
}

/// Zero-capture closure (just a function wrapper)
pub fn ZeroClosure(comptime ArgT: type, comptime RetT: type, comptime func: fn (ArgT) RetT) type {
    return struct {
        const Self = @This();

        pub fn call(_: Self, arg: ArgT) RetT {
            return func(arg);
        }
    };
}

/// Typed closure with explicit argument/return types (eliminates anytype monomorphization)
/// Each closure has ONE .call() signature - no per-call-site monomorphization
///
/// Why this matters:
/// - AnyClosure with anytype: 200 closures × 5 arg types = 1000 monomorphizations
/// - TypedClosure: 200 closures × 1 fixed signature = 200 monomorphizations
///
/// The inner function still uses anytype (unavoidable for Python's dynamic typing),
/// but the closure wrapper has a fixed signature, breaking the O(n²) explosion.

/// TypedClosure0 - no arguments, explicit return type
pub fn TypedClosure0(comptime CaptureT: type, comptime RetT: type, comptime func: anytype) type {
    return struct {
        const Self = @This();
        captures: CaptureT,
        __name__: []const u8 = "",
        __dict__: ?*anyopaque = null,

        pub fn call(self: Self) RetT {
            return @call(.auto, func, .{self.captures});
        }
    };
}

/// TypedClosure1 - one argument with explicit types
pub fn TypedClosure1(comptime CaptureT: type, comptime Arg1T: type, comptime RetT: type, comptime func: anytype) type {
    return struct {
        const Self = @This();
        captures: CaptureT,
        __name__: []const u8 = "",
        __dict__: ?*anyopaque = null,

        pub fn call(self: Self, arg1: Arg1T) RetT {
            return @call(.auto, func, .{ self.captures, arg1 });
        }
    };
}

/// TypedClosure2 - two arguments with explicit types
pub fn TypedClosure2(comptime CaptureT: type, comptime Arg1T: type, comptime Arg2T: type, comptime RetT: type, comptime func: anytype) type {
    return struct {
        const Self = @This();
        captures: CaptureT,
        __name__: []const u8 = "",
        __dict__: ?*anyopaque = null,

        pub fn call(self: Self, arg1: Arg1T, arg2: Arg2T) RetT {
            return @call(.auto, func, .{ self.captures, arg1, arg2 });
        }
    };
}

/// TypedClosure3 - three arguments with explicit types
pub fn TypedClosure3(comptime CaptureT: type, comptime Arg1T: type, comptime Arg2T: type, comptime Arg3T: type, comptime RetT: type, comptime func: anytype) type {
    return struct {
        const Self = @This();
        captures: CaptureT,
        __name__: []const u8 = "",
        __dict__: ?*anyopaque = null,

        pub fn call(self: Self, arg1: Arg1T, arg2: Arg2T, arg3: Arg3T) RetT {
            return @call(.auto, func, .{ self.captures, arg1, arg2, arg3 });
        }
    };
}

/// TypedClosure4 - four arguments with explicit types
pub fn TypedClosure4(comptime CaptureT: type, comptime Arg1T: type, comptime Arg2T: type, comptime Arg3T: type, comptime Arg4T: type, comptime RetT: type, comptime func: anytype) type {
    return struct {
        const Self = @This();
        captures: CaptureT,
        __name__: []const u8 = "",
        __dict__: ?*anyopaque = null,

        pub fn call(self: Self, arg1: Arg1T, arg2: Arg2T, arg3: Arg3T, arg4: Arg4T) RetT {
            return @call(.auto, func, .{ self.captures, arg1, arg2, arg3, arg4 });
        }
    };
}

/// TypedClosure5 - five arguments with explicit types
pub fn TypedClosure5(comptime CaptureT: type, comptime Arg1T: type, comptime Arg2T: type, comptime Arg3T: type, comptime Arg4T: type, comptime Arg5T: type, comptime RetT: type, comptime func: anytype) type {
    return struct {
        const Self = @This();
        captures: CaptureT,
        __name__: []const u8 = "",
        __dict__: ?*anyopaque = null,

        pub fn call(self: Self, arg1: Arg1T, arg2: Arg2T, arg3: Arg3T, arg4: Arg4T, arg5: Arg5T) RetT {
            return @call(.auto, func, .{ self.captures, arg1, arg2, arg3, arg4, arg5 });
        }
    };
}

/// TypedClosure6 - six arguments with explicit types
pub fn TypedClosure6(comptime CaptureT: type, comptime Arg1T: type, comptime Arg2T: type, comptime Arg3T: type, comptime Arg4T: type, comptime Arg5T: type, comptime Arg6T: type, comptime RetT: type, comptime func: anytype) type {
    return struct {
        const Self = @This();
        captures: CaptureT,
        __name__: []const u8 = "",
        __dict__: ?*anyopaque = null,

        pub fn call(self: Self, arg1: Arg1T, arg2: Arg2T, arg3: Arg3T, arg4: Arg4T, arg5: Arg5T, arg6: Arg6T) RetT {
            return @call(.auto, func, .{ self.captures, arg1, arg2, arg3, arg4, arg5, arg6 });
        }
    };
}

/// TypedClosure7 - seven arguments with explicit types
pub fn TypedClosure7(comptime CaptureT: type, comptime Arg1T: type, comptime Arg2T: type, comptime Arg3T: type, comptime Arg4T: type, comptime Arg5T: type, comptime Arg6T: type, comptime Arg7T: type, comptime RetT: type, comptime func: anytype) type {
    return struct {
        const Self = @This();
        captures: CaptureT,
        __name__: []const u8 = "",
        __dict__: ?*anyopaque = null,

        pub fn call(self: Self, arg1: Arg1T, arg2: Arg2T, arg3: Arg3T, arg4: Arg4T, arg5: Arg5T, arg6: Arg6T, arg7: Arg7T) RetT {
            return @call(.auto, func, .{ self.captures, arg1, arg2, arg3, arg4, arg5, arg6, arg7 });
        }
    };
}

/// Legacy AnyClosure aliases - kept for backward compatibility during transition
/// These use @TypeOf inference which causes monomorphization but ensures type correctness
/// TODO: Remove once all codegen uses TypedClosure

/// Universal closure with any-typed arguments (for Python closures with mixed types)
/// Uses anytype parameters to accept strings, ints, etc.
/// Return type is inferred from the wrapped function's return type
pub fn AnyClosure0(comptime CaptureT: type, comptime func: anytype) type {
    const RetType = @typeInfo(@TypeOf(func)).@"fn".return_type.?;
    return struct {
        const Self = @This();
        captures: CaptureT,
        __name__: []const u8 = "",
        __dict__: ?*anyopaque = null,

        pub fn call(self: Self) RetType {
            return @call(.auto, func, .{self.captures});
        }
    };
}

/// Universal 1-arg closure with anytype
pub fn AnyClosure1(comptime CaptureT: type, comptime func: anytype) type {
    return struct {
        const Self = @This();
        captures: CaptureT,
        __name__: []const u8 = "",
        __dict__: ?*anyopaque = null,

        pub fn call(self: Self, arg: anytype) @TypeOf(@call(.auto, func, .{ self.captures, arg })) {
            return @call(.auto, func, .{ self.captures, arg });
        }
    };
}

/// Universal 2-arg closure with anytype
pub fn AnyClosure2(comptime CaptureT: type, comptime func: anytype) type {
    return struct {
        const Self = @This();
        captures: CaptureT,
        __name__: []const u8 = "",
        __dict__: ?*anyopaque = null,

        pub fn call(self: Self, arg1: anytype, arg2: anytype) @TypeOf(@call(.auto, func, .{ self.captures, arg1, arg2 })) {
            return @call(.auto, func, .{ self.captures, arg1, arg2 });
        }
    };
}

/// Universal 3-arg closure with anytype
pub fn AnyClosure3(comptime CaptureT: type, comptime func: anytype) type {
    return struct {
        const Self = @This();
        captures: CaptureT,
        __name__: []const u8 = "",
        __dict__: ?*anyopaque = null,

        pub fn call(self: Self, arg1: anytype, arg2: anytype, arg3: anytype) @TypeOf(@call(.auto, func, .{ self.captures, arg1, arg2, arg3 })) {
            return @call(.auto, func, .{ self.captures, arg1, arg2, arg3 });
        }
    };
}

/// Universal 4-arg closure with anytype
pub fn AnyClosure4(comptime CaptureT: type, comptime func: anytype) type {
    return struct {
        const Self = @This();
        captures: CaptureT,
        __name__: []const u8 = "",
        __dict__: ?*anyopaque = null,

        pub fn call(self: Self, arg1: anytype, arg2: anytype, arg3: anytype, arg4: anytype) @TypeOf(@call(.auto, func, .{ self.captures, arg1, arg2, arg3, arg4 })) {
            return @call(.auto, func, .{ self.captures, arg1, arg2, arg3, arg4 });
        }
    };
}

/// Universal 5-arg closure with anytype
pub fn AnyClosure5(comptime CaptureT: type, comptime func: anytype) type {
    return struct {
        const Self = @This();
        captures: CaptureT,
        __name__: []const u8 = "",
        __dict__: ?*anyopaque = null,

        pub fn call(self: Self, arg1: anytype, arg2: anytype, arg3: anytype, arg4: anytype, arg5: anytype) @TypeOf(@call(.auto, func, .{ self.captures, arg1, arg2, arg3, arg4, arg5 })) {
            return @call(.auto, func, .{ self.captures, arg1, arg2, arg3, arg4, arg5 });
        }
    };
}

/// Universal 6-arg closure with anytype
pub fn AnyClosure6(comptime CaptureT: type, comptime func: anytype) type {
    return struct {
        const Self = @This();
        captures: CaptureT,
        __name__: []const u8 = "",
        __dict__: ?*anyopaque = null,

        pub fn call(self: Self, arg1: anytype, arg2: anytype, arg3: anytype, arg4: anytype, arg5: anytype, arg6: anytype) @TypeOf(@call(.auto, func, .{ self.captures, arg1, arg2, arg3, arg4, arg5, arg6 })) {
            return @call(.auto, func, .{ self.captures, arg1, arg2, arg3, arg4, arg5, arg6 });
        }
    };
}

/// Universal 7-arg closure with anytype
pub fn AnyClosure7(comptime CaptureT: type, comptime func: anytype) type {
    return struct {
        const Self = @This();
        captures: CaptureT,
        __name__: []const u8 = "",
        __dict__: ?*anyopaque = null,

        pub fn call(self: Self, arg1: anytype, arg2: anytype, arg3: anytype, arg4: anytype, arg5: anytype, arg6: anytype, arg7: anytype) @TypeOf(@call(.auto, func, .{ self.captures, arg1, arg2, arg3, arg4, arg5, arg6, arg7 })) {
            return @call(.auto, func, .{ self.captures, arg1, arg2, arg3, arg4, arg5, arg6, arg7 });
        }
    };
}

/// Partial function application (functools.partial replacement)
///
/// PROBLEM: Original codegen generates inline struct per partial() call:
///   const Partial = struct {
///       captured: @TypeOf(_captured),
///       func: @TypeOf(_func),
///       pub fn call(__self: @This(), extra_args: anytype) @TypeOf(_func(_captured ++ extra_args)) { ... }
///   };
/// This causes O(n²) compilation time - 546 instances in test_argparse.zig alone!
///
/// SOLUTION: Move struct definition to runtime library, compile ONCE.
/// Codegen just instantiates the type with specific func/captured types.
/// This reduces 546 inline struct definitions to 546 type instantiations,
/// which Zig compiles much faster.
///
/// Key insight: The struct definition itself is the bottleneck, not the type params.
/// By defining the struct once in the runtime, Zig can reuse the compiled code.
pub fn Partial(comptime FuncT: type, comptime CapturedT: type) type {
    return struct {
        const Self = @This();
        func: FuncT,
        captured: CapturedT,

        /// Call with additional arguments (variadic via anytype)
        /// Return type inferred from @call, not pre-evaluated with @TypeOf
        pub inline fn call(self: Self, extra_args: anytype) @TypeOf(@call(.auto, self.func, self.captured ++ extra_args)) {
            return @call(.auto, self.func, self.captured ++ extra_args);
        }
    };
}
