/// TypeFactory - Runtime representation of Python types/classes
/// Allows types to be stored in lists, passed to functions, and called to create instances
const std = @import("std");

/// A callable type wrapper - stores __name__ and a constructor function
/// This is the common type that can be stored in lists when classes are used as values
pub const PyType = struct {
    /// The name of the type (e.g., "bytes", "CustomBytes")
    __name__: []const u8,

    /// Constructor function pointer - takes allocator and bytes, returns struct with __base_value__
    /// Returns void* (opaque) to allow different return types
    _construct: *const fn (std.mem.Allocator, []const u8) callconv(.C) ?*anyopaque,

    /// Construct an instance from bytes
    pub fn construct(self: PyType, allocator: std.mem.Allocator, arg: []const u8) ?*anyopaque {
        return self._construct(allocator, arg);
    }
};

/// Create a PyType for the builtin bytes type
pub fn bytesType() PyType {
    const BytesWrapper = struct {
        fn construct(_: std.mem.Allocator, arg: []const u8) callconv(.C) ?*anyopaque {
            // For bytes, just return the slice pointer as-is
            // This is safe because the caller knows to interpret it as []const u8
            return @ptrFromInt(@intFromPtr(arg.ptr));
        }
    };
    return .{
        .__name__ = "bytes",
        ._construct = &BytesWrapper.construct,
    };
}

/// Create a PyType for the builtin bytearray type
pub fn bytearrayType() PyType {
    const BytearrayWrapper = struct {
        fn construct(_: std.mem.Allocator, arg: []const u8) callconv(.C) ?*anyopaque {
            return @ptrFromInt(@intFromPtr(arg.ptr));
        }
    };
    return .{
        .__name__ = "bytearray",
        ._construct = &BytearrayWrapper.construct,
    };
}

/// Create a PyType for the builtin memoryview type
pub fn memoryviewType() PyType {
    const MemoryviewWrapper = struct {
        fn construct(_: std.mem.Allocator, arg: []const u8) callconv(.C) ?*anyopaque {
            return @ptrFromInt(@intFromPtr(arg.ptr));
        }
    };
    return .{
        .__name__ = "memoryview",
        ._construct = &MemoryviewWrapper.construct,
    };
}

/// Helper to convert a []const u8 to the value stored in the type with __base_value__
pub fn toBaseValue(comptime T: type, result: ?*anyopaque) T {
    if (result) |ptr| {
        if (@typeInfo(T) == .pointer and @typeInfo(T).pointer.size == .slice) {
            // Result is a slice - reconstruct from pointer
            const slice_ptr: [*]const u8 = @ptrCast(ptr);
            // We lose length info - need to fix this
            return slice_ptr[0..0];
        }
        // For struct types with __base_value__
        if (@hasField(T, "__base_value__")) {
            // The ptr points to the bytes
            const slice_ptr: [*]const u8 = @ptrCast(ptr);
            return T{ .__base_value__ = slice_ptr[0..0] };
        }
    }
    // Default - return empty for slice types
    if (@typeInfo(T) == .pointer and @typeInfo(T).pointer.size == .slice) {
        return &[_]u8{};
    }
    @compileError("Cannot convert result to type " ++ @typeName(T));
}

test "PyType basics" {
    const bytes_factory = bytesType();
    try std.testing.expectEqualStrings("bytes", bytes_factory.__name__);
}
