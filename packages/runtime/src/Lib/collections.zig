//! Python 'collections' module - Container datatypes
//!
//! This module implements specialized container datatypes providing
//! alternatives to Python's general purpose built-in containers.
//!
//! Mirrors: CPython Lib/collections/__init__.py

const std = @import("std");

// ============================================================================
// Re-export collections.abc (alias for _collections_abc)
// In Python: from collections.abc import MappingView, KeysView, etc.
// ============================================================================
pub const abc = @import("_collections_abc.zig");

// ============================================================================
// Re-export all collections modules
// ============================================================================
pub const namedtuple = @import("collections/namedtuple.zig").namedtuple;
pub const Deque = @import("collections/deque.zig").Deque;
pub const Counter = @import("collections/counter.zig").Counter;
pub const OrderedDict = @import("collections/ordereddict.zig").OrderedDict;
pub const DefaultDict = @import("collections/defaultdict.zig").DefaultDict;
pub const ChainMap = @import("collections/chainmap.zig").ChainMap;
pub const UserDict = @import("collections/userdict.zig").UserDict;
pub const UserList = @import("collections/userlist.zig").UserList;
pub const UserString = @import("collections/userstring.zig").UserString;

// ============================================================================
// Tests - Re-run all component tests
// ============================================================================
test {
    @import("std").testing.refAllDecls(@This());
    _ = @import("collections/namedtuple.zig");
    _ = @import("collections/deque.zig");
    _ = @import("collections/counter.zig");
    _ = @import("collections/ordereddict.zig");
    _ = @import("collections/defaultdict.zig");
    _ = @import("collections/userlist.zig");
    _ = @import("collections/userstring.zig");
}
