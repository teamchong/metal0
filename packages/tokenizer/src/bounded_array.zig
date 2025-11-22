/// Removed from the Zig standard library in https://github.com/ziglang/zig/pull/24699/
/// Copied from Bun: https://github.com/oven-sh/bun/blob/main/src/collections/bounded_array.zig
///
/// A structure with an array and a length, that can be used as a slice.
///
/// Useful to pass around small arrays whose exact size is only known at
/// runtime, but whose maximum size is known at comptime, without requiring
/// an `Allocator`.
pub fn BoundedArray(comptime T: type, comptime buffer_capacity: usize) type {
    return BoundedArrayAligned(T, .fromByteUnits(@alignOf(T)), buffer_capacity);
}

pub fn BoundedArrayAligned(
    comptime T: type,
    comptime alignment: Alignment,
    comptime buffer_capacity: usize,
) type {
    return struct {
        const Self = @This();
        buffer: [buffer_capacity]T align(alignment.toByteUnits()) = undefined,
        len: Length = 0,

        const Length = std.math.ByteAlignedInt(std.math.IntFittingRange(0, buffer_capacity));

        pub const Buffer = @FieldType(Self, "buffer");

        /// Set the actual length of the slice.
        /// Returns error.Overflow if it exceeds the length of the backing array.
        pub fn init(len: usize) error{Overflow}!Self {
            if (len > buffer_capacity) return error.Overflow;
            return Self{ .len = @intCast(len) };
        }

        /// View the internal array as a slice whose size was previously set.
        pub fn slice(self: anytype) switch (@TypeOf(&self.buffer)) {
            *align(alignment.toByteUnits()) [buffer_capacity]T => []align(alignment.toByteUnits()) T,
            *align(alignment.toByteUnits()) const [buffer_capacity]T => []align(alignment.toByteUnits()) const T,
            else => unreachable,
        } {
            return self.buffer[0..self.len];
        }

        /// View the internal array as a constant slice whose size was previously set.
        pub fn constSlice(self: *const Self) []align(alignment.toByteUnits()) const T {
            return self.slice();
        }

        /// Remove all elements from the slice.
        pub fn clear(self: *Self) void {
            self.len = 0;
        }

        /// Return the element at index `i` of the slice.
        pub fn get(self: Self, i: usize) T {
            return self.constSlice()[i];
        }

        /// Check that the slice can hold at least `additional_count` items.
        pub fn ensureUnusedCapacity(self: Self, additional_count: usize) error{Overflow}!void {
            if (self.len + additional_count > buffer_capacity) {
                return error.Overflow;
            }
        }

        /// Increase length by 1, returning a pointer to the new item.
        pub fn addOne(self: *Self) error{Overflow}!*T {
            try self.ensureUnusedCapacity(1);
            return self.addOneAssumeCapacity();
        }

        /// Increase length by 1, returning pointer to the new item.
        /// Asserts that there is space for the new item.
        pub fn addOneAssumeCapacity(self: *Self) *T {
            std.debug.assert(self.len < buffer_capacity);
            self.len += 1;
            return &self.slice()[self.len - 1];
        }

        /// Remove and return the last element from the slice, or return `null` if the slice is empty.
        pub fn pop(self: *Self) ?T {
            if (self.len == 0) return null;
            const item = self.get(self.len - 1);
            self.len -= 1;
            return item;
        }

        /// Extend the slice by 1 element.
        pub fn append(self: *Self, item: T) error{Overflow}!void {
            const new_item_ptr = try self.addOne();
            new_item_ptr.* = item;
        }
    };
}

const std = @import("std");
const Alignment = std.mem.Alignment;
