//! Pickle value types
const std = @import("std");
const hashmap_helper = @import("utils.hashmap_helper");

/// Value types that can be pickled
pub const PickleValue = union(enum) {
    none: void,
    bool: bool,
    int: i64,
    float: f64,
    string: []const u8,
    bytes: []const u8,
    tuple: []const PickleValue,
    list: std.ArrayList(PickleValue),
    dict: hashmap_helper.StringHashMap(PickleValue),
    set: std.AutoHashMap(u64, void),
    // For iterators - store type info and state
    iterator: Iterator,
    // Reference to memo
    memo_ref: usize,

    pub const Iterator = struct {
        type_name: []const u8, // "tuple_iterator", "list_iterator", "reversed"
        data: []const PickleValue, // The underlying data
        index: usize, // Current position
    };

    pub fn deinit(self: *PickleValue, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .list => |*l| {
                for (l.items) |*item| {
                    var mut_item = item.*;
                    mut_item.deinit(allocator);
                }
                l.deinit(allocator);
            },
            .dict => |*d| {
                var it = d.iterator();
                while (it.next()) |entry| {
                    var val = entry.value_ptr.*;
                    val.deinit(allocator);
                }
                d.deinit();
            },
            .tuple => |t| {
                for (t) |*item| {
                    var mut_item = @constCast(item).*;
                    mut_item.deinit(allocator);
                }
                allocator.free(t);
            },
            else => {},
        }
    }
};

/// Pickle errors
pub const PicklingError = error{
    UnsupportedType,
    InvalidOpcode,
    StackUnderflow,
    InvalidMemoRef,
    UnexpectedEOF,
    InvalidData,
    OutOfMemory,
};

pub const UnpicklingError = PicklingError;
