/// List conversion helpers for Python list() builtin
/// Handles tuple-to-list, string-to-list, and generic iterable conversions
/// Extracted from runtime.zig to reduce file size
const std = @import("std");
const object_zig = @import("../Objects/object.zig");
const PyValue = object_zig.PyValue;
const pylist = @import("../Objects/listobject.zig");
const NativeList = pylist.NativeList;

/// Convert a tuple to a list (ArrayList) - used by list() codegen
pub fn listFromTuple(allocator: std.mem.Allocator, tuple: anytype) std.ArrayListUnmanaged(PyValue) {
    const T = @TypeOf(tuple);
    const info = @typeInfo(T);

    var list = std.ArrayListUnmanaged(PyValue){};

    if (info == .@"struct") {
        // Handle anonymous struct (tuple)
        inline for (info.@"struct".fields) |field| {
            const val = @field(tuple, field.name);
            list.append(allocator, PyValue.from(val)) catch {};
        }
    } else if (info == .array) {
        // Handle fixed-size array
        for (tuple) |item| {
            list.append(allocator, PyValue.from(item)) catch {};
        }
    }

    return list;
}

/// Convert a string to a list of single-character strings - used by list() codegen
pub fn listFromString(allocator: std.mem.Allocator, str: []const u8) std.ArrayListUnmanaged([]const u8) {
    var list = std.ArrayListUnmanaged([]const u8){};

    var i: usize = 0;
    while (i < str.len) {
        // Get UTF-8 character length
        const byte = str[i];
        const char_len: usize = if (byte < 0x80) 1 else if (byte < 0xE0) 2 else if (byte < 0xF0) 3 else 4;
        const end = @min(i + char_len, str.len);

        // Allocate a copy of the character slice
        const char_copy = allocator.dupe(u8, str[i..end]) catch {
            i = end;
            continue;
        };
        list.append(allocator, char_copy) catch {};
        i = end;
    }

    return list;
}

/// Convert any iterable to a list (generic fallback) - used by list() codegen
pub fn listFromAny(allocator: std.mem.Allocator, iterable: anytype) std.ArrayListUnmanaged(PyValue) {
    const T = @TypeOf(iterable);
    const info = @typeInfo(T);

    var list = std.ArrayListUnmanaged(PyValue){};

    // Handle strings
    if (T == []const u8 or T == []u8) {
        var i: usize = 0;
        while (i < iterable.len) {
            const byte = iterable[i];
            const char_len: usize = if (byte < 0x80) 1 else if (byte < 0xE0) 2 else if (byte < 0xF0) 3 else 4;
            const end = @min(i + char_len, iterable.len);
            const char_copy = allocator.dupe(u8, iterable[i..end]) catch {
                i = end;
                continue;
            };
            list.append(allocator, PyValue.from(char_copy)) catch {};
            i = end;
        }
        return list;
    }

    // Handle slices
    if (info == .pointer and info.pointer.size == .slice) {
        for (iterable) |item| {
            list.append(allocator, PyValue.from(item)) catch {};
        }
        return list;
    }

    // Handle arrays
    if (info == .array) {
        for (iterable) |item| {
            list.append(allocator, PyValue.from(item)) catch {};
        }
        return list;
    }

    // Handle pointer to struct (e.g., *TupleSubclass)
    if (info == .pointer and info.pointer.size == .one) {
        const child_info = @typeInfo(info.pointer.child);
        if (child_info == .@"struct") {
            // Check for tuple subclass with __base_value__
            if (@hasField(info.pointer.child, "__base_value__")) {
                const base = iterable.__base_value__;
                const BaseType = @TypeOf(base);
                // If __base_value__ is PyValue, extract the tuple/list data
                if (BaseType == PyValue) {
                    switch (base) {
                        .tuple => |items| {
                            for (items) |item| {
                                list.append(allocator, item) catch {};
                            }
                            return list;
                        },
                        .list => |items| {
                            for (items) |item| {
                                list.append(allocator, item) catch {};
                            }
                            return list;
                        },
                        else => {},
                    }
                }
            }
        }
    }

    // Handle structs (tuples and tuple subclasses)
    if (info == .@"struct") {
        // Check for tuple subclass with __base_value__ - iterate over base tuple
        if (@hasField(T, "__base_value__")) {
            const base = iterable.__base_value__;
            const BaseType = @TypeOf(base);
            // If __base_value__ is PyValue, extract the tuple/list data
            if (BaseType == PyValue) {
                switch (base) {
                    .tuple => |items| {
                        for (items) |item| {
                            list.append(allocator, item) catch {};
                        }
                        return list;
                    },
                    .list => |items| {
                        for (items) |item| {
                            list.append(allocator, item) catch {};
                        }
                        return list;
                    },
                    else => {},
                }
            }
            const base_info = @typeInfo(BaseType);
            if (base_info == .@"struct") {
                inline for (base_info.@"struct".fields) |field| {
                    const val = @field(base, field.name);
                    list.append(allocator, PyValue.from(val)) catch {};
                }
                return list;
            }
        }
        // Regular tuple - iterate over fields
        inline for (info.@"struct".fields) |field| {
            const val = @field(iterable, field.name);
            list.append(allocator, PyValue.from(val)) catch {};
        }
        return list;
    }

    // Handle NativeList first (has .items which is ArrayList, not slice)
    if (T == NativeList) {
        for (iterable.items.items) |item| {
            list.append(allocator, item) catch {}; // NativeList items are already PyValue
        }
        return list;
    }

    // Handle ArrayListUnmanaged
    if (info == .@"struct" and @hasField(T, "items")) {
        for (iterable.items) |item| {
            list.append(allocator, PyValue.from(item)) catch {};
        }
        return list;
    }

    return list;
}
