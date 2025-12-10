//! CPython source: Lib/_collections_abc.py
//!
//! Abstract Base Classes (ABCs) for collections.
//! These are marker types used for isinstance() checks.
//!
//! Mirrors: CPython Lib/_collections_abc.py

const std = @import("std");

// ============================================================================
// ABC Markers - Empty structs used as type markers for isinstance() checks
// ============================================================================

/// Marker for hashable types - objects that can be hashed
pub const Hashable = struct {
    pub const __abstractmethods__ = &[_][]const u8{"__hash__"};
};

/// Marker for awaitable types - objects that can be awaited
pub const Awaitable = struct {
    pub const __abstractmethods__ = &[_][]const u8{"__await__"};
};

/// Marker for coroutine types
pub const Coroutine = struct {
    pub const __abstractmethods__ = &[_][]const u8{ "send", "throw", "close" };
};

/// Marker for async iterable types
pub const AsyncIterable = struct {
    pub const __abstractmethods__ = &[_][]const u8{"__aiter__"};
};

/// Marker for async iterator types
pub const AsyncIterator = struct {
    pub const __abstractmethods__ = &[_][]const u8{"__anext__"};
};

/// Marker for async generator types
pub const AsyncGenerator = struct {
    pub const __abstractmethods__ = &[_][]const u8{ "asend", "athrow", "aclose" };
};

/// Marker for iterable types - objects that can be iterated
pub const Iterable = struct {
    pub const __abstractmethods__ = &[_][]const u8{"__iter__"};
};

/// Marker for iterator types - objects that produce values via next()
pub const Iterator = struct {
    pub const __abstractmethods__ = &[_][]const u8{"__next__"};
};

/// Marker for reversible types - objects that support reversed()
pub const Reversible = struct {
    pub const __abstractmethods__ = &[_][]const u8{"__reversed__"};
};

/// Marker for generator types
pub const Generator = struct {
    pub const __abstractmethods__ = &[_][]const u8{ "send", "throw", "close" };
};

// ============================================================================
// Container ABCs
// ============================================================================

/// Marker for container types - objects that support `in` operator
pub const Container = struct {
    pub const __abstractmethods__ = &[_][]const u8{"__contains__"};
};

/// Marker for sized types - objects that have len()
pub const Sized = struct {
    pub const __abstractmethods__ = &[_][]const u8{"__len__"};
};

/// Marker for callable types - objects that can be called
pub const Callable = struct {
    pub const __abstractmethods__ = &[_][]const u8{"__call__"};
};

/// Collection combines Sized, Iterable, Container
pub const Collection = struct {
    pub const __abstractmethods__ = &[_][]const u8{ "__len__", "__iter__", "__contains__" };
};

// ============================================================================
// Sequence ABCs
// ============================================================================

/// Marker for sequence types - ordered collections with index access
pub const Sequence = struct {
    pub const __abstractmethods__ = &[_][]const u8{ "__getitem__", "__len__" };
};

/// Marker for mutable sequence types - sequences that can be modified
pub const MutableSequence = struct {
    pub const __abstractmethods__ = &[_][]const u8{ "__getitem__", "__setitem__", "__delitem__", "__len__", "insert" };
};

/// Marker for byte string types
pub const ByteString = struct {
    pub const __abstractmethods__ = &[_][]const u8{};
};

// ============================================================================
// Set ABCs
// ============================================================================

/// Marker for set types - unordered collections without duplicates
pub const Set = struct {
    pub const __abstractmethods__ = &[_][]const u8{ "__contains__", "__iter__", "__len__" };
};

/// Marker for mutable set types
pub const MutableSet = struct {
    pub const __abstractmethods__ = &[_][]const u8{ "__contains__", "__iter__", "__len__", "add", "discard" };
};

// ============================================================================
// Mapping ABCs
// ============================================================================

/// Marker for mapping types - key-value collections
pub const Mapping = struct {
    pub const __abstractmethods__ = &[_][]const u8{ "__getitem__", "__iter__", "__len__" };

    /// Register a virtual subclass (for ABC protocol)
    pub fn register(allocator: std.mem.Allocator, cls: anytype) !void {
        _ = allocator;
        _ = cls;
        // No-op for now - ABC registration not fully supported
    }
};

/// Marker for mutable mapping types
pub const MutableMapping = struct {
    pub const __abstractmethods__ = &[_][]const u8{ "__getitem__", "__setitem__", "__delitem__", "__iter__", "__len__" };
};

// ============================================================================
// View ABCs
// ============================================================================

/// Base marker for mapping views
pub const MappingView = struct {
    pub const __abstractmethods__ = &[_][]const u8{"__len__"};
};

/// Marker for keys view
pub const KeysView = struct {
    pub const __abstractmethods__ = &[_][]const u8{ "__len__", "__iter__", "__contains__" };
};

/// Marker for values view
pub const ValuesView = struct {
    pub const __abstractmethods__ = &[_][]const u8{ "__len__", "__iter__" };
};

/// Marker for items view
pub const ItemsView = struct {
    pub const __abstractmethods__ = &[_][]const u8{ "__len__", "__iter__", "__contains__" };
};
