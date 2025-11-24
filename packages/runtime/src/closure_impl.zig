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
