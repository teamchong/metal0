//! CPython source: Lib/_collections_abc.py
//!
//! Provides ABCs for the collections module.
//!
//! Mirrors: CPython Lib/_collections_abc.py

const std = @import("std");

// ============================================================================
// ABC Markers (used for type checking)
// ============================================================================

/// Marker for hashable types
pub const Hashable = struct {
    pub fn __hash__(self: anytype) usize {
        _ = self;
        return 0;
    }
};

/// Marker for awaitable types
pub const Awaitable = struct {
    pub fn __await__(self: anytype) anytype {
        return self;
    }
};

/// Marker for coroutine types
pub const Coroutine = struct {
    pub fn send(self: anytype, value: anytype) anytype {
        _ = self;
        _ = value;
        return null;
    }

    pub fn throw(self: anytype, typ: anytype, val: anytype, tb: anytype) anytype {
        _ = self;
        _ = typ;
        _ = val;
        _ = tb;
        return null;
    }

    pub fn close(self: anytype) void {
        _ = self;
    }
};

/// Marker for async iterable types
pub const AsyncIterable = struct {
    pub fn __aiter__(self: anytype) anytype {
        return self;
    }
};

/// Marker for async iterator types
pub const AsyncIterator = struct {
    pub fn __anext__(self: anytype) anytype {
        _ = self;
        return null;
    }
};

/// Marker for async generator types
pub const AsyncGenerator = struct {
    pub fn asend(self: anytype, value: anytype) anytype {
        _ = self;
        _ = value;
        return null;
    }

    pub fn athrow(self: anytype, typ: anytype, val: anytype, tb: anytype) anytype {
        _ = self;
        _ = typ;
        _ = val;
        _ = tb;
        return null;
    }

    pub fn aclose(self: anytype) void {
        _ = self;
    }
};

/// Marker for iterable types
pub const Iterable = struct {
    pub fn __iter__(self: anytype) anytype {
        return self;
    }
};

/// Marker for iterator types
pub const Iterator = struct {
    pub fn __next__(self: anytype) anytype {
        _ = self;
        return null;
    }
};

/// Marker for reversible types
pub const Reversible = struct {
    pub fn __reversed__(self: anytype) anytype {
        return self;
    }
};

/// Marker for generator types
pub const Generator = struct {
    pub fn send(self: anytype, value: anytype) anytype {
        _ = self;
        _ = value;
        return null;
    }

    pub fn throw(self: anytype, typ: anytype, val: anytype, tb: anytype) anytype {
        _ = self;
        _ = typ;
        _ = val;
        _ = tb;
        return null;
    }

    pub fn close(self: anytype) void {
        _ = self;
    }
};

// ============================================================================
// Container ABCs
// ============================================================================

/// Marker for sized types (have __len__)
pub const Sized = struct {
    pub fn __len__(self: anytype) usize {
        _ = self;
        return 0;
    }
};

/// Marker for container types (have __contains__)
pub const Container = struct {
    pub fn __contains__(self: anytype, item: anytype) bool {
        _ = self;
        _ = item;
        return false;
    }
};

/// Marker for callable types
pub const Callable = struct {
    pub fn __call__(self: anytype, args: anytype) anytype {
        _ = self;
        _ = args;
        return null;
    }
};

// ============================================================================
// Collection ABCs
// ============================================================================

/// Collection combines Sized, Iterable, Container
pub const Collection = struct {
    pub fn __len__(self: anytype) usize {
        _ = self;
        return 0;
    }

    pub fn __iter__(self: anytype) anytype {
        return self;
    }

    pub fn __contains__(self: anytype, item: anytype) bool {
        _ = self;
        _ = item;
        return false;
    }
};

// ============================================================================
// Sequence ABCs
// ============================================================================

/// Marker for sequence types
pub const Sequence = struct {
    pub fn __getitem__(self: anytype, index: anytype) anytype {
        _ = self;
        _ = index;
        return null;
    }

    pub fn __len__(self: anytype) usize {
        _ = self;
        return 0;
    }

    pub fn __contains__(self: anytype, item: anytype) bool {
        _ = self;
        _ = item;
        return false;
    }

    pub fn __iter__(self: anytype) anytype {
        return self;
    }

    pub fn __reversed__(self: anytype) anytype {
        return self;
    }

    pub fn index(self: anytype, value: anytype, start: usize, stop: usize) ?usize {
        _ = self;
        _ = value;
        _ = start;
        _ = stop;
        return null;
    }

    pub fn count(self: anytype, value: anytype) usize {
        _ = self;
        _ = value;
        return 0;
    }
};

/// Marker for mutable sequence types
pub const MutableSequence = struct {
    pub fn __setitem__(self: anytype, index: anytype, value: anytype) void {
        _ = self;
        _ = index;
        _ = value;
    }

    pub fn __delitem__(self: anytype, index: anytype) void {
        _ = self;
        _ = index;
    }

    pub fn insert(self: anytype, index: usize, value: anytype) void {
        _ = self;
        _ = index;
        _ = value;
    }

    pub fn append(self: anytype, value: anytype) void {
        _ = self;
        _ = value;
    }

    pub fn clear(self: anytype) void {
        _ = self;
    }

    pub fn reverse(self: anytype) void {
        _ = self;
    }

    pub fn extend(self: anytype, values: anytype) void {
        _ = self;
        _ = values;
    }

    pub fn pop(self: anytype, index: ?isize) anytype {
        _ = self;
        _ = index;
        return null;
    }

    pub fn remove(self: anytype, value: anytype) void {
        _ = self;
        _ = value;
    }
};

// ============================================================================
// Set ABCs
// ============================================================================

/// Marker for set types
pub const Set = struct {
    pub fn __contains__(self: anytype, item: anytype) bool {
        _ = self;
        _ = item;
        return false;
    }

    pub fn __iter__(self: anytype) anytype {
        return self;
    }

    pub fn __len__(self: anytype) usize {
        _ = self;
        return 0;
    }

    pub fn __le__(self: anytype, other: anytype) bool {
        _ = self;
        _ = other;
        return false;
    }

    pub fn __lt__(self: anytype, other: anytype) bool {
        _ = self;
        _ = other;
        return false;
    }

    pub fn __eq__(self: anytype, other: anytype) bool {
        _ = self;
        _ = other;
        return false;
    }

    pub fn __gt__(self: anytype, other: anytype) bool {
        _ = self;
        _ = other;
        return false;
    }

    pub fn __ge__(self: anytype, other: anytype) bool {
        _ = self;
        _ = other;
        return false;
    }

    pub fn __and__(self: anytype, other: anytype) anytype {
        _ = self;
        _ = other;
        return null;
    }

    pub fn __or__(self: anytype, other: anytype) anytype {
        _ = self;
        _ = other;
        return null;
    }

    pub fn __sub__(self: anytype, other: anytype) anytype {
        _ = self;
        _ = other;
        return null;
    }

    pub fn __xor__(self: anytype, other: anytype) anytype {
        _ = self;
        _ = other;
        return null;
    }

    pub fn isdisjoint(self: anytype, other: anytype) bool {
        _ = self;
        _ = other;
        return false;
    }
};

/// Marker for mutable set types
pub const MutableSet = struct {
    pub fn add(self: anytype, value: anytype) void {
        _ = self;
        _ = value;
    }

    pub fn discard(self: anytype, value: anytype) void {
        _ = self;
        _ = value;
    }

    pub fn remove(self: anytype, value: anytype) void {
        _ = self;
        _ = value;
    }

    pub fn pop(self: anytype) anytype {
        _ = self;
        return null;
    }

    pub fn clear(self: anytype) void {
        _ = self;
    }
};

// ============================================================================
// Mapping ABCs
// ============================================================================

/// Marker for mapping types
pub const Mapping = struct {
    pub fn __getitem__(self: anytype, key: anytype) anytype {
        _ = self;
        _ = key;
        return null;
    }

    pub fn __contains__(self: anytype, key: anytype) bool {
        _ = self;
        _ = key;
        return false;
    }

    pub fn __iter__(self: anytype) anytype {
        return self;
    }

    pub fn __len__(self: anytype) usize {
        _ = self;
        return 0;
    }

    pub fn keys(self: anytype) anytype {
        _ = self;
        return null;
    }

    pub fn values(self: anytype) anytype {
        _ = self;
        return null;
    }

    pub fn items(self: anytype) anytype {
        _ = self;
        return null;
    }

    pub fn get(self: anytype, key: anytype, default: anytype) anytype {
        _ = self;
        _ = key;
        return default;
    }

    pub fn __eq__(self: anytype, other: anytype) bool {
        _ = self;
        _ = other;
        return false;
    }
};

/// Marker for mutable mapping types
pub const MutableMapping = struct {
    pub fn __setitem__(self: anytype, key: anytype, value: anytype) void {
        _ = self;
        _ = key;
        _ = value;
    }

    pub fn __delitem__(self: anytype, key: anytype) void {
        _ = self;
        _ = key;
    }

    pub fn pop(self: anytype, key: anytype, default: anytype) anytype {
        _ = self;
        _ = key;
        return default;
    }

    pub fn popitem(self: anytype) anytype {
        _ = self;
        return null;
    }

    pub fn clear(self: anytype) void {
        _ = self;
    }

    pub fn update(self: anytype, other: anytype) void {
        _ = self;
        _ = other;
    }

    pub fn setdefault(self: anytype, key: anytype, default: anytype) anytype {
        _ = self;
        _ = key;
        return default;
    }
};

// ============================================================================
// View ABCs
// ============================================================================

/// Marker for mapping view types
pub const MappingView = struct {
    mapping: ?*anyopaque,

    pub fn __len__(self: anytype) usize {
        _ = self;
        return 0;
    }
};

/// Marker for keys view
pub const KeysView = struct {
    pub fn __contains__(self: anytype, key: anytype) bool {
        _ = self;
        _ = key;
        return false;
    }

    pub fn __iter__(self: anytype) anytype {
        return self;
    }
};

/// Marker for items view
pub const ItemsView = struct {
    pub fn __contains__(self: anytype, item: anytype) bool {
        _ = self;
        _ = item;
        return false;
    }

    pub fn __iter__(self: anytype) anytype {
        return self;
    }
};

/// Marker for values view
pub const ValuesView = struct {
    pub fn __contains__(self: anytype, value: anytype) bool {
        _ = self;
        _ = value;
        return false;
    }

    pub fn __iter__(self: anytype) anytype {
        return self;
    }
};

// ============================================================================
// Virtual Subclass Registration
// ============================================================================

/// Check if a type implements an ABC
pub fn isInstance(comptime T: type, comptime ABC: type) bool {
    // Check if T has all required methods of ABC
    const abc_info = @typeInfo(ABC);
    if (abc_info != .@"struct") return false;

    const t_info = @typeInfo(T);
    if (t_info != .@"struct") return false;

    // Check for required methods
    inline for (abc_info.@"struct".decls) |decl| {
        if (!@hasDecl(T, decl.name)) {
            return false;
        }
    }
    return true;
}

// ============================================================================
// Tests
// ============================================================================

test "ABC markers exist" {
    // Just verify the types exist
    _ = Hashable;
    _ = Iterable;
    _ = Iterator;
    _ = Sized;
    _ = Container;
    _ = Callable;
    _ = Collection;
    _ = Sequence;
    _ = MutableSequence;
    _ = Set;
    _ = MutableSet;
    _ = Mapping;
    _ = MutableMapping;
}

test "Async ABCs exist" {
    _ = Awaitable;
    _ = Coroutine;
    _ = AsyncIterable;
    _ = AsyncIterator;
    _ = AsyncGenerator;
}

test "View ABCs exist" {
    _ = MappingView;
    _ = KeysView;
    _ = ItemsView;
    _ = ValuesView;
}
