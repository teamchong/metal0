/// _collections - C accelerator module for collections
/// Provides: deque, defaultdict, OrderedDict, Counter, ChainMap, UserDict, UserList, UserString, namedtuple
const std = @import("std");

// Re-export all collection types
pub const deque = @import("deque.zig");
pub const Deque = deque.Deque;

pub const defaultdict = @import("defaultdict.zig");
pub const DefaultDict = defaultdict.DefaultDict;

pub const ordereddict = @import("ordereddict.zig");
pub const OrderedDict = ordereddict.OrderedDict;

pub const counter = @import("counter.zig");
pub const Counter = counter.Counter;
pub const _count_elements = counter._count_elements;

pub const chainmap = @import("chainmap.zig");
pub const ChainMap = chainmap.ChainMap;

pub const userdict = @import("userdict.zig");
pub const UserDict = userdict.UserDict;

pub const userlist = @import("userlist.zig");
pub const UserList = userlist.UserList;

pub const userstring = @import("userstring.zig");
pub const UserString = userstring.UserString;

pub const namedtuple = @import("namedtuple.zig");
pub const NamedTuple = namedtuple.NamedTuple;
pub const namedtupleFactory = namedtuple.namedtupleFactory;

// Tests
test "deque basic operations" {
    const allocator = std.testing.allocator;
    var d = Deque(i32).init(allocator);
    defer d.deinit();

    try d.append(1);
    try d.append(2);
    try d.appendleft(0);

    try std.testing.expectEqual(@as(usize, 3), d.len());
    try std.testing.expectEqual(@as(?i32, 0), d.get(0));
    try std.testing.expectEqual(@as(?i32, 1), d.get(1));
    try std.testing.expectEqual(@as(?i32, 2), d.get(2));

    try std.testing.expectEqual(@as(?i32, 2), d.pop());
    try std.testing.expectEqual(@as(?i32, 0), d.popleft());
    try std.testing.expectEqual(@as(usize, 1), d.len());
}

test "deque with maxlen" {
    const allocator = std.testing.allocator;
    var d = Deque(i32).initWithMaxlen(allocator, 3);
    defer d.deinit();

    try d.append(1);
    try d.append(2);
    try d.append(3);
    try d.append(4); // Should evict 1

    try std.testing.expectEqual(@as(usize, 3), d.len());
    try std.testing.expectEqual(@as(?i32, 2), d.get(0)); // 1 was evicted
}

test "counter basic" {
    const allocator = std.testing.allocator;
    var c = Counter(i32).init(allocator);
    defer c.deinit();

    try c.increment(1);
    try c.increment(1);
    try c.increment(2);

    try std.testing.expectEqual(@as(i64, 2), c.get(1));
    try std.testing.expectEqual(@as(i64, 1), c.get(2));
    try std.testing.expectEqual(@as(i64, 0), c.get(3));
}

test "ordereddict basic" {
    const allocator = std.testing.allocator;
    var od = OrderedDict(i32, i32).init(allocator);
    defer od.deinit();

    try od.put(1, 100);
    try od.put(2, 200);
    try od.put(3, 300);

    try std.testing.expectEqual(@as(?i32, 100), od.get(1));
    try std.testing.expectEqual(@as(usize, 3), od.count());

    const keys = od.keys();
    try std.testing.expectEqual(@as(i32, 1), keys[0]);
    try std.testing.expectEqual(@as(i32, 2), keys[1]);
    try std.testing.expectEqual(@as(i32, 3), keys[2]);
}
