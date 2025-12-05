/// Data Structures Package
///
/// Generic data structures for high-performance applications:
/// - BoundedArray: Fixed-capacity stack-allocated array
/// - BumpAllocator: O(1) arena-style allocator
/// - ObjectPool: Thread-safe/thread-local object pooling

pub const BoundedArray = @import("bounded_array.zig").BoundedArray;
pub const BoundedArrayAligned = @import("bounded_array.zig").BoundedArrayAligned;

pub const BumpAllocator = @import("bump_allocator.zig").BumpAllocator;

pub const ObjectPool = @import("pool.zig").ObjectPool;
pub const SinglyLinkedList = @import("pool.zig").SinglyLinkedList;
