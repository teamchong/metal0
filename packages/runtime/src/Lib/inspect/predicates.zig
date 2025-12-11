//! Type checking predicates for runtime inspection
//!
//! Provides functions to check object types and properties:
//! - ismodule, isclass, isfunction, ismethod
//! - isgenerator, iscoroutine, isawaitable
//! - isbuiltin, isroutine, isabstract
//! - isdatadescriptor, ismemberdescriptor, ismethoddescriptor
//! - callable, hasattr

const std = @import("std");

// ============================================================================
// Type checking predicates
// ============================================================================

/// Check if the object is a module
pub fn ismodule(comptime T: type) bool {
    // In Zig, modules are namespaces at comptime
    return @typeInfo(T) == .@"struct" and @hasDecl(T, "__module__");
}

/// Check if the object is a class (struct in Zig)
pub fn isclass(comptime T: type) bool {
    return @typeInfo(T) == .@"struct";
}

/// Check if the object is a method
pub fn ismethod(comptime T: type) bool {
    const info = @typeInfo(T);
    if (info == .@"fn") {
        // Methods have a self parameter
        return info.@"fn".params.len > 0;
    }
    return false;
}

/// Check if the object is a function
pub fn isfunction(comptime T: type) bool {
    return @typeInfo(T) == .@"fn";
}

/// Check if the object is a generator function
pub fn isgeneratorfunction(comptime T: type) bool {
    // Zig doesn't have native generators, but we can check for iterator patterns
    _ = T;
    return false;
}

/// Check if the object is a generator
pub fn isgenerator(comptime T: type) bool {
    // Check if it implements the iterator pattern
    return @hasDecl(T, "next");
}

/// Check if the object is a coroutine function
pub fn iscoroutinefunction(comptime T: type) bool {
    // Check if it's an async function
    const info = @typeInfo(T);
    if (info == .@"fn") {
        return info.@"fn".is_async;
    }
    return false;
}

/// Check if the object is a coroutine
pub fn iscoroutine(_: anytype) bool {
    return false; // Zig handles async differently
}

/// Check if the object is awaitable
pub fn isawaitable(comptime T: type) bool {
    return @hasDecl(T, "await") or iscoroutinefunction(T);
}

/// Check if the object is async generator function
pub fn isasyncgenfunction(comptime T: type) bool {
    return iscoroutinefunction(T) and isgenerator(T);
}

/// Check if the object is async generator
pub fn isasyncgen(comptime T: type) bool {
    return isasyncgenfunction(T);
}

/// Check if the object is a traceback
pub fn istraceback(_: anytype) bool {
    return false; // Zig doesn't have tracebacks in the same way
}

/// Check if the object is a frame
pub fn isframe(_: anytype) bool {
    return false; // Zig doesn't have frames in the same way
}

/// Check if the object is a code object
pub fn iscode(_: anytype) bool {
    return false; // Zig doesn't have code objects
}

/// Check if the object is a built-in function
pub fn isbuiltin(comptime T: type) bool {
    return @typeInfo(T) == .@"fn";
}

/// Check if the object is a routine (function, method, or builtin)
pub fn isroutine(comptime T: type) bool {
    return isfunction(T) or ismethod(T) or isbuiltin(T);
}

/// Check if the object appears to be abstract
pub fn isabstract(comptime T: type) bool {
    // Check if it has abstractmethod declarations
    return @hasDecl(T, "__abstractmethods__");
}

/// Check if the object is a data descriptor
pub fn isdatadescriptor(comptime T: type) bool {
    return @hasDecl(T, "__get__") and @hasDecl(T, "__set__");
}

/// Check if the object is a member descriptor
pub fn ismemberdescriptor(comptime T: type) bool {
    return @hasDecl(T, "__get__") and !@hasDecl(T, "__set__");
}

/// Check if the object is a method descriptor
pub fn ismethoddescriptor(comptime T: type) bool {
    return @hasDecl(T, "__get__") and !@hasDecl(T, "__set__") and !isdatadescriptor(T);
}

// ============================================================================
// Attributes
// ============================================================================

/// Check if an object has an attribute
pub fn hasattr(comptime T: type, comptime name: []const u8) bool {
    return @hasField(T, name) or @hasDecl(T, name);
}

// ============================================================================
// Callable inspection
// ============================================================================

/// Check if the object is callable
pub fn callable(comptime T: type) bool {
    const info = @typeInfo(T);
    return info == .@"fn" or (info == .@"struct" and @hasDecl(T, "call"));
}
