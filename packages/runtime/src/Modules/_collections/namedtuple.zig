/// namedtuple - Factory function for creating tuple subclasses with named fields
const std = @import("std");
const Allocator = std.mem.Allocator;
const allocator_helper = @import("utils.allocator_helper");
const hashmap_helper = @import("utils.hashmap_helper");

/// NamedTuple - Runtime representation of a namedtuple
/// This provides the base functionality for namedtuple instances at runtime.
/// The actual namedtuple factory is handled by codegen which creates specialized types.
pub fn NamedTuple(comptime field_count: usize) type {
    return struct {
        _fields: [field_count][]const u8,
        _values: [field_count]i64, // Using i64 for generic value storage
        _typename: []const u8,

        const Self = @This();

        pub fn init(typename: []const u8, field_names: [field_count][]const u8, values: [field_count]i64) Self {
            return .{
                ._fields = field_names,
                ._values = values,
                ._typename = typename,
            };
        }

        /// Get field value by index
        pub fn get(self: Self, index: usize) ?i64 {
            if (index >= field_count) return null;
            return self._values[index];
        }

        /// Get field value by name
        pub fn getByName(self: Self, name: []const u8) ?i64 {
            for (self._fields, 0..) |field, i| {
                if (std.mem.eql(u8, field, name)) {
                    return self._values[i];
                }
            }
            return null;
        }

        /// Get field index by name
        pub fn fieldIndex(self: Self, name: []const u8) ?usize {
            for (self._fields, 0..) |field, i| {
                if (std.mem.eql(u8, field, name)) {
                    return i;
                }
            }
            return null;
        }

        /// _asdict() - Return a new dict mapping field names to values
        pub fn _asdict(self: Self, allocator: Allocator) !hashmap_helper.StringHashMap(i64) {
            var dict = hashmap_helper.StringHashMap(i64).init(allocator);
            for (self._fields, 0..) |field, i| {
                try dict.put(field, self._values[i]);
            }
            return dict;
        }

        /// _replace(**kwargs) - Return new instance with specified fields replaced
        pub fn _replace(self: Self, replacements: anytype) Self {
            var new_values = self._values;
            inline for (std.meta.fields(@TypeOf(replacements))) |field| {
                const idx = self.fieldIndex(field.name);
                if (idx) |i| {
                    new_values[i] = @field(replacements, field.name);
                }
            }
            return .{
                ._fields = self._fields,
                ._values = new_values,
                ._typename = self._typename,
            };
        }

        /// _make(iterable) - Make a new instance from existing sequence/iterable
        pub fn _make(typename: []const u8, field_names: [field_count][]const u8, values: []const i64) !Self {
            if (values.len != field_count) return error.ValueError;
            var arr: [field_count]i64 = undefined;
            for (values, 0..) |v, i| {
                arr[i] = v;
            }
            return Self.init(typename, field_names, arr);
        }

        /// __len__ - Return number of fields
        pub fn len(_: Self) usize {
            return field_count;
        }

        /// __iter__ - Iterate over values (for tuple iteration)
        pub fn iter(self: *const Self) NamedTupleIterator {
            return NamedTupleIterator.init(self);
        }

        const NamedTupleIterator = struct {
            nt: *const Self,
            index: usize,

            fn init(nt: *const Self) NamedTupleIterator {
                return .{ .nt = nt, .index = 0 };
            }

            pub fn next(it: *NamedTupleIterator) ?i64 {
                if (it.index >= field_count) return null;
                const value = it.nt._values[it.index];
                it.index += 1;
                return value;
            }
        };

        /// __eq__ - Compare two namedtuples
        pub fn eql(self: Self, other: Self) bool {
            if (!std.mem.eql(u8, self._typename, other._typename)) return false;
            for (self._values, 0..) |v, i| {
                if (v != other._values[i]) return false;
            }
            return true;
        }

        /// __hash__ - Hash the namedtuple (based on values)
        pub fn hash(self: Self) u64 {
            var h: u64 = 0;
            for (self._values) |v| {
                h = h *% 31 +% @as(u64, @bitCast(v));
            }
            return h;
        }

        /// _fields - Return tuple of field names
        pub fn fields(self: Self) [field_count][]const u8 {
            return self._fields;
        }

        /// _field_defaults - Return dict of default values (empty for base)
        pub fn _field_defaults(_: Self) hashmap_helper.StringHashMap(i64) {
            return hashmap_helper.StringHashMap(i64).init(allocator_helper.fast_allocator);
        }
    };
}

/// Helper to create a namedtuple factory at comptime
/// Usage: const Point = namedtupleFactory("Point", .{"x", "y"});
pub fn namedtupleFactory(comptime typename: []const u8, comptime field_names: anytype) type {
    const field_count = field_names.len;

    return struct {
        data: NamedTuple(field_count),

        const Self = @This();
        pub const _typename = typename;
        pub const _fields = field_names;

        pub fn init(values: [field_count]i64) Self {
            return .{
                .data = NamedTuple(field_count).init(typename, field_names, values),
            };
        }

        pub fn get(self: Self, index: usize) ?i64 {
            return self.data.get(index);
        }

        pub fn getByName(self: Self, name: []const u8) ?i64 {
            return self.data.getByName(name);
        }

        pub fn _asdict(self: Self, allocator: Allocator) !hashmap_helper.StringHashMap(i64) {
            return self.data._asdict(allocator);
        }

        pub fn len(_: Self) usize {
            return field_count;
        }

        pub fn eql(self: Self, other: Self) bool {
            return self.data.eql(other.data);
        }
    };
}
