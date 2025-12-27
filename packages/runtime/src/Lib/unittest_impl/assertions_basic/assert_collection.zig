/// metal0 unittest assertions - collection and membership assertions
const std = @import("std");
const runner = @import("../../unittest/runner.zig");
const runtime = @import("../../../runtime.zig");
const helpers = @import("equality_helpers.zig");

const pythonEql = helpers.pythonEql;

/// Helper to check if a type is string-like
inline fn isStringLikeInline(comptime T: type) bool {
    const info = @typeInfo(T);
    // Handle optional types - unwrap and check inner type
    if (info == .optional) {
        return isStringLikeInline(info.optional.child);
    }
    if (info != .pointer) return false;
    const ptr = info.pointer;
    if (ptr.size == .slice and ptr.child == u8) return true;
    if (ptr.size == .one) {
        const child_info = @typeInfo(ptr.child);
        if (child_info == .array and child_info.array.child == u8) return true;
    }
    return false;
}

/// Assertion: assertIn(item, container) - item must be in container
pub fn assertIn(item: anytype, container: anytype) !void {
    const ItemType = @TypeOf(item);
    const ContainerType = @TypeOf(container);

    const is_string_in_string = comptime blk: {
        const item_is_str = isStringLikeInline(ItemType);
        const container_is_str = isStringLikeInline(ContainerType);
        break :blk item_is_str and container_is_str;
    };

    const found = if (comptime is_string_in_string) string_blk: {
        // Handle optional container - unwrap if present, fail if null
        const container_slice: []const u8 = if (comptime @typeInfo(ContainerType) == .optional)
            (container orelse break :string_blk false)
        else
            container;
        // Handle optional item - unwrap if present, fail if null
        const item_slice: []const u8 = if (comptime @typeInfo(ItemType) == .optional)
            (item orelse break :string_blk false)
        else
            item;
        break :string_blk std.mem.indexOf(u8, container_slice, item_slice) != null;
    } else elem_blk: {
        const container_info = @typeInfo(ContainerType);

        if (comptime container_info == .@"struct") {
            if (comptime @hasField(ContainerType, "items")) {
                for (container.items) |elem| {
                    if (pythonEql(elem, item)) break :elem_blk true;
                }
                break :elem_blk false;
            } else if (comptime @hasDecl(ContainerType, "contains")) {
                const contains_info = @typeInfo(@TypeOf(ContainerType.contains));
                const KeyType = if (contains_info == .@"fn" and contains_info.@"fn".params.len >= 2)
                    contains_info.@"fn".params[1].type orelse void
                else
                    void;
                const ItemT = @TypeOf(item);
                if (comptime ItemT == f64 and KeyType == u64) {
                    break :elem_blk container.contains(@bitCast(item));
                } else if (comptime ItemT == KeyType) {
                    break :elem_blk container.contains(item);
                } else {
                    break :elem_blk false;
                }
            } else if (comptime container_info.@"struct".is_tuple) {
                inline for (container) |elem| {
                    if (pythonEql(elem, item)) break :elem_blk true;
                }
                break :elem_blk false;
            } else if (comptime @hasDecl(ContainerType, "__contains__")) {
                break :elem_blk container.__contains__(item);
            } else {
                break :elem_blk false;
            }
        } else if (comptime container_info == .pointer) {
            break :elem_blk false;
        } else if (comptime container_info == .optional) {
            // Handle optional types - unwrap and iterate if present
            if (container) |unwrapped| {
                const unwrapped_info = @typeInfo(@TypeOf(unwrapped));
                if (comptime unwrapped_info == .pointer and unwrapped_info.pointer.size == .slice) {
                    for (unwrapped) |elem| {
                        if (pythonEql(elem, item)) break :elem_blk true;
                    }
                }
            }
            break :elem_blk false;
        } else {
            for (container) |elem| {
                if (pythonEql(elem, item)) break :elem_blk true;
            }
            break :elem_blk false;
        }
    };

    if (!found) {
        std.debug.print("AssertionError: {any} not in container\n", .{item});
        if (runner.global_result) |result| {
            result.addFail("assertIn failed") catch {};
        }
        return error.AssertionFailed;
    } else {
        if (runner.global_result) |result| {
            result.addPass();
        }
    }
}

/// Assertion: assertNotIn(item, container) - item must not be in container
pub fn assertNotIn(item: anytype, container: anytype) !void {
    const ItemType = @TypeOf(item);
    const ContainerType = @TypeOf(container);

    const is_string_in_string = comptime blk: {
        const item_is_str = isStringLikeInline(ItemType);
        const container_is_str = isStringLikeInline(ContainerType);
        break :blk item_is_str and container_is_str;
    };

    const found = if (comptime is_string_in_string) string_blk: {
        // Handle optional container - unwrap if present, fail if null
        const container_slice: []const u8 = if (comptime @typeInfo(ContainerType) == .optional)
            (container orelse break :string_blk false)
        else
            container;
        // Handle optional item - unwrap if present, fail if null
        const item_slice: []const u8 = if (comptime @typeInfo(ItemType) == .optional)
            (item orelse break :string_blk false)
        else
            item;
        break :string_blk std.mem.indexOf(u8, container_slice, item_slice) != null;
    } else elem_blk: {
        const container_info = @typeInfo(ContainerType);

        if (comptime container_info == .@"struct") {
            if (comptime @hasField(ContainerType, "items")) {
                for (container.items) |elem| {
                    if (pythonEql(elem, item)) break :elem_blk true;
                }
                break :elem_blk false;
            } else if (comptime @hasDecl(ContainerType, "contains")) {
                const contains_info = @typeInfo(@TypeOf(ContainerType.contains));
                const KeyType = if (contains_info == .@"fn" and contains_info.@"fn".params.len >= 2)
                    contains_info.@"fn".params[1].type orelse void
                else
                    void;
                const ItemT = @TypeOf(item);
                if (comptime ItemT == f64 and KeyType == u64) {
                    break :elem_blk container.contains(@bitCast(item));
                } else if (comptime ItemT == KeyType) {
                    break :elem_blk container.contains(item);
                } else {
                    break :elem_blk false;
                }
            } else if (comptime container_info.@"struct".is_tuple) {
                inline for (container) |elem| {
                    if (pythonEql(elem, item)) break :elem_blk true;
                }
                break :elem_blk false;
            } else if (comptime @hasDecl(ContainerType, "__contains__")) {
                break :elem_blk container.__contains__(item);
            } else {
                break :elem_blk false;
            }
        } else if (comptime container_info == .pointer) {
            break :elem_blk false;
        } else if (comptime container_info == .optional) {
            // Handle optional types - unwrap and iterate if present
            if (container) |unwrapped| {
                const unwrapped_info = @typeInfo(@TypeOf(unwrapped));
                if (comptime unwrapped_info == .pointer and unwrapped_info.pointer.size == .slice) {
                    for (unwrapped) |elem| {
                        if (pythonEql(elem, item)) break :elem_blk true;
                    }
                }
            }
            break :elem_blk false;
        } else {
            for (container) |elem| {
                if (pythonEql(elem, item)) break :elem_blk true;
            }
            break :elem_blk false;
        }
    };

    if (found) {
        std.debug.print("AssertionError: {any} unexpectedly in container\n", .{item});
        if (runner.global_result) |result| {
            result.addFail("assertNotIn failed") catch {};
        }
        return error.AssertionFailed;
    } else {
        if (runner.global_result) |result| {
            result.addPass();
        }
    }
}

/// Assertion: assertHasAttr(obj, attr_name) - check if object has attribute
pub fn assertHasAttr(obj: anytype, attr_name: []const u8) !void {
    const T = @TypeOf(obj);
    const type_info = @typeInfo(T);

    const has_attr = switch (type_info) {
        .@"struct" => |s| blk: {
            inline for (s.fields) |field| {
                if (std.mem.eql(u8, field.name, attr_name)) {
                    break :blk true;
                }
            }
            break :blk false;
        },
        .pointer => |ptr| inner_blk: {
            if (ptr.size == .one) {
                const child_info = @typeInfo(ptr.child);
                if (child_info == .@"struct") {
                    inline for (child_info.@"struct".fields) |field| {
                        if (std.mem.eql(u8, field.name, attr_name)) {
                            break :inner_blk true;
                        }
                    }
                }
            }
            break :inner_blk false;
        },
        else => false,
    };

    if (!has_attr) {
        std.debug.print("AssertionError: object has no attribute '{s}'\n", .{attr_name});
        if (runner.global_result) |result| {
            result.addFail("assertHasAttr failed") catch {};
        }
        return error.AssertionFailed;
    } else {
        if (runner.global_result) |result| {
            result.addPass();
        }
    }
}

/// Assertion: assertNotHasAttr(obj, attr_name) - check if object does NOT have attribute
pub fn assertNotHasAttr(obj: anytype, attr_name: []const u8) !void {
    const T = @TypeOf(obj);
    const type_info = @typeInfo(T);

    const has_attr = switch (type_info) {
        .@"struct" => |s| blk: {
            inline for (s.fields) |field| {
                if (std.mem.eql(u8, field.name, attr_name)) {
                    break :blk true;
                }
            }
            break :blk false;
        },
        .pointer => |ptr| inner_blk: {
            if (ptr.size == .one) {
                const child_info = @typeInfo(ptr.child);
                if (child_info == .@"struct") {
                    inline for (child_info.@"struct".fields) |field| {
                        if (std.mem.eql(u8, field.name, attr_name)) {
                            break :inner_blk true;
                        }
                    }
                }
            }
            break :inner_blk false;
        },
        else => false,
    };

    if (has_attr) {
        std.debug.print("AssertionError: object unexpectedly has attribute '{s}'\n", .{attr_name});
        if (runner.global_result) |result| {
            result.addFail("assertNotHasAttr failed") catch {};
        }
        return error.AssertionFailed;
    } else {
        if (runner.global_result) |result| {
            result.addPass();
        }
    }
}
