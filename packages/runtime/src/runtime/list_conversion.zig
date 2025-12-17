/// List conversion helpers for Python list() builtin
/// Handles tuple-to-list, string-to-list, and generic iterable conversions
/// Extracted from runtime.zig to reduce file size
const std = @import("std");
const object_zig = @import("../Objects/object.zig");
const PyValue = object_zig.PyValue;
const pylist = @import("../Objects/listobject.zig");
const NativeList = pylist.NativeList;

// =============================================================================
// CONCRETE PyValue CONVERSIONS (compile ONCE - no monomorphization)
// =============================================================================

/// Convert PyValue tuple to list - compiles once
fn listFromPyValue(allocator: std.mem.Allocator, value: PyValue) std.ArrayListUnmanaged(PyValue) {
    var list = std.ArrayListUnmanaged(PyValue){};
    switch (value) {
        .tuple => |items| {
            for (items) |item| {
                list.append(allocator, item) catch unreachable;
            }
        },
        .list => |l| {
            for (l.items) |item| {
                list.append(allocator, item) catch unreachable;
            }
        },
        .string => |s| {
            var i: usize = 0;
            while (i < s.len) {
                const byte = s[i];
                const char_len: usize = if (byte < 0x80) 1 else if (byte < 0xE0) 2 else if (byte < 0xF0) 3 else 4;
                const end = @min(i + char_len, s.len);
                const char_copy = allocator.dupe(u8, s[i..end]) catch {
                    i = end;
                    continue;
                };
                list.append(allocator, PyValue.from(char_copy)) catch unreachable;
                i = end;
            }
        },
        else => {},
    }
    return list;
}

// =============================================================================
// ANYTYPE WRAPPERS (dispatch to concrete for PyValue)
// =============================================================================

/// Convert a tuple to a list (ArrayList) - used by list() codegen
pub fn listFromTuple(allocator: std.mem.Allocator, tuple: anytype) std.ArrayListUnmanaged(PyValue) {
    const T = @TypeOf(tuple);
    const info = @typeInfo(T);

    // Fast path: PyValue - use concrete function to avoid monomorphization
    if (T == PyValue) {
        return listFromPyValue(allocator, tuple);
    }

    var list = std.ArrayListUnmanaged(PyValue){};

    if (info == .@"struct") {
        // Handle anonymous struct (tuple)
        inline for (info.@"struct".fields) |field| {
            const val = @field(tuple, field.name);
            list.append(allocator, PyValue.from(val)) catch unreachable;
        }
    } else if (info == .array) {
        // Handle fixed-size array
        for (tuple) |item| {
            list.append(allocator, PyValue.from(item)) catch unreachable;
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
        list.append(allocator, char_copy) catch unreachable;
        i = end;
    }

    return list;
}

/// Convert any iterable to a list (generic fallback) - used by list() codegen
pub fn listFromAny(allocator: std.mem.Allocator, iterable: anytype) std.ArrayListUnmanaged(PyValue) {
    const T = @TypeOf(iterable);
    const info = @typeInfo(T);

    // Fast path: PyValue - use concrete function to avoid monomorphization
    if (T == PyValue) {
        return listFromPyValue(allocator, iterable);
    }

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
            list.append(allocator, PyValue.from(item)) catch unreachable;
        }
        return list;
    }

    // Handle arrays
    if (info == .array) {
        for (iterable) |item| {
            list.append(allocator, PyValue.from(item)) catch unreachable;
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
                                list.append(allocator, item) catch unreachable;
                            }
                            return list;
                        },
                        .list => |l| {
                            for (l.items) |item| {
                                list.append(allocator, item) catch unreachable;
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
                            list.append(allocator, item) catch unreachable;
                        }
                        return list;
                    },
                    .list => |l| {
                        for (l.items) |item| {
                            list.append(allocator, item) catch unreachable;
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
                    list.append(allocator, PyValue.from(val)) catch unreachable;
                }
                return list;
            }
        }
        // Regular tuple - iterate over fields
        inline for (info.@"struct".fields) |field| {
            const val = @field(iterable, field.name);
            list.append(allocator, PyValue.from(val)) catch unreachable;
        }
        return list;
    }

    // Handle NativeList first (has .items which is ArrayList, not slice)
    if (T == NativeList) {
        for (iterable.items.items) |item| {
            list.append(allocator, item) catch unreachable; // NativeList items are already PyValue
        }
        return list;
    }

    // Handle ArrayListUnmanaged
    if (info == .@"struct" and @hasField(T, "items")) {
        for (iterable.items) |item| {
            list.append(allocator, PyValue.from(item)) catch unreachable;
        }
        return list;
    }

    return list;
}

/// Compare an iterator/iterable with a list/array for equality
/// Used by assertEqual(list(iter), expected) optimization
/// Returns true if all elements match, false otherwise
/// This is more efficient than converting to list first (listFromAny) and then comparing
pub fn listEquals(allocator: std.mem.Allocator, iterable: anytype, expected: anytype) bool {
    const T = @TypeOf(iterable);
    const E = @TypeOf(expected);
    const info_t = @typeInfo(T);
    const info_e = @typeInfo(E);
    const equality = @import("equality.zig");

    // Get expected items slice
    const expected_items = blk: {
        if (info_e == .@"struct" and @hasField(E, "items")) {
            break :blk expected.items;
        } else if (info_e == .pointer and info_e.pointer.size == .slice) {
            break :blk expected;
        } else if (info_e == .array) {
            break :blk &expected;
        } else {
            break :blk expected;
        }
    };

    // Handle iterators with next() method
    if (info_t == .@"struct" and @hasDecl(T, "next")) {
        var iter = iterable;
        var i: usize = 0;
        while (true) {
            const next_val = iter.next() catch |err| {
                if (err == error.StopIteration) break;
                return false;
            };
            if (i >= expected_items.len) return false; // More items than expected
            if (!equality.pyAnyEql(next_val, expected_items[i])) return false;
            i += 1;
        }
        return i == expected_items.len; // All items matched
    }

    // Handle pointer to iterator
    if (info_t == .pointer and info_t.pointer.size == .one) {
        const child_info = @typeInfo(info_t.pointer.child);
        if (child_info == .@"struct" and @hasDecl(info_t.pointer.child, "next")) {
            var iter = iterable;
            var i: usize = 0;
            while (true) {
                const next_val = iter.next() catch |err| {
                    if (err == error.StopIteration) break;
                    return false;
                };
                if (i >= expected_items.len) return false;
                if (!equality.pyAnyEql(next_val, expected_items[i])) return false;
                i += 1;
            }
            return i == expected_items.len;
        }
    }

    // Handle slices directly
    if (info_t == .pointer and info_t.pointer.size == .slice) {
        if (iterable.len != expected_items.len) return false;
        for (iterable, 0..) |item, i| {
            if (!equality.pyAnyEql(item, expected_items[i])) return false;
        }
        return true;
    }

    // Handle arrays
    if (info_t == .array) {
        if (iterable.len != expected_items.len) return false;
        for (iterable, 0..) |item, i| {
            if (!equality.pyAnyEql(item, expected_items[i])) return false;
        }
        return true;
    }

    // Handle ArrayListUnmanaged
    if (info_t == .@"struct" and @hasField(T, "items")) {
        if (iterable.items.len != expected_items.len) return false;
        for (iterable.items, 0..) |item, i| {
            if (!equality.pyAnyEql(item, expected_items[i])) return false;
        }
        return true;
    }

    // Fallback: convert to list and compare
    _ = allocator;
    return false;
}
