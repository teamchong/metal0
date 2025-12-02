/// Python queue module - Synchronized queue classes
const std = @import("std");
const h = @import("mod_helper.zig");

const QueueStruct = "struct { items: std.ArrayList([]const u8), maxsize: i64 = 0, mutex: std.Thread.Mutex = .{}, pub fn init(maxsize: i64) @This() { return @This(){ .items = std.ArrayList([]const u8){}, .maxsize = maxsize }; } pub fn put(__self: *@This(), item: []const u8) void { __self.mutex.lock(); defer __self.mutex.unlock(); __self.items.append(__global_allocator, item) catch {}; } pub fn get(__self: *@This()) ?[]const u8 { __self.mutex.lock(); defer __self.mutex.unlock(); if (__self.items.items.len == 0) return null; return __self.items.orderedRemove(0); } pub fn put_nowait(__self: *@This(), item: []const u8) void { __self.put(item); } pub fn get_nowait(__self: *@This()) ?[]const u8 { return __self.get(); } pub fn empty(__self: *@This()) bool { return __self.items.items.len == 0; } pub fn full(__self: *@This()) bool { return __self.maxsize > 0 and @as(i64, @intCast(__self.items.items.len)) >= __self.maxsize; } pub fn qsize(__self: *@This()) i64 { return @as(i64, @intCast(__self.items.items.len)); } pub fn task_done(__self: *@This()) void { _ = __self; } pub fn join(__self: *@This()) void { _ = __self; } }.init(0)";
const LifoQueueStruct = "struct { items: std.ArrayList([]const u8), maxsize: i64 = 0, mutex: std.Thread.Mutex = .{}, pub fn init(maxsize: i64) @This() { return @This(){ .items = std.ArrayList([]const u8){}, .maxsize = maxsize }; } pub fn put(__self: *@This(), item: []const u8) void { __self.mutex.lock(); defer __self.mutex.unlock(); __self.items.append(__global_allocator, item) catch {}; } pub fn get(__self: *@This()) ?[]const u8 { __self.mutex.lock(); defer __self.mutex.unlock(); return __self.items.popOrNull(); } pub fn empty(__self: *@This()) bool { return __self.items.items.len == 0; } pub fn qsize(__self: *@This()) i64 { return @as(i64, @intCast(__self.items.items.len)); } }.init(0)";

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "Queue", h.c(QueueStruct) }, .{ "LifoQueue", h.c(LifoQueueStruct) },
    .{ "PriorityQueue", h.c(QueueStruct) }, .{ "SimpleQueue", h.c(QueueStruct) },
    .{ "Empty", h.c("\"Empty\"") }, .{ "Full", h.c("\"Full\"") },
});
