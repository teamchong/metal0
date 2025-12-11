/// Pattern matching support for ceval
/// Mirrors part of cpython/Python/ceval.c
const std = @import("std");
const runtime = @import("../../runtime.zig");

/// Match exception group
pub fn exceptionGroupMatch(
    exc_value: ?*anyopaque,
    match_type: ?*anyopaque,
) struct { ?*anyopaque, ?*anyopaque } {
    const exc = exc_value orelse return .{ null, null };
    const type_to_match = match_type orelse return .{ null, null };

    const exc_obj: *runtime.PyObject = @ptrCast(@alignCast(exc));
    const type_obj: *runtime.PyObject = @ptrCast(@alignCast(type_to_match));

    if (exceptionTypeMatches(exc_obj, type_obj)) {
        return .{ exc, null };
    }
    return .{ null, exc };
}

fn exceptionTypeMatches(exc: *runtime.PyObject, type_obj: *runtime.PyObject) bool {
    const exc_type = exc.ob_type orelse return false;
    const match_type_ptr = type_obj.ob_type orelse return false;

    if (exc_type == match_type_ptr) return true;

    const exc_name = exc_type.tp_name;
    const match_name = match_type_ptr.tp_name;

    if (std.mem.eql(u8, std.mem.span(exc_name), std.mem.span(match_name))) {
        return true;
    }

    return runtime.isSubclass(exc_type, match_type_ptr);
}

/// Match mapping keys for pattern matching
pub fn matchKeys(
    map: ?*anyopaque,
    keys: ?*anyopaque,
) ?*anyopaque {
    const map_ptr = map orelse return null;
    const keys_ptr = keys orelse return null;

    const map_obj: *runtime.PyObject = @ptrCast(@alignCast(map_ptr));
    const keys_obj: *runtime.PyObject = @ptrCast(@alignCast(keys_ptr));

    if (!runtime.PyDict_Check(map_obj)) {
        return null;
    }

    const keys_type = runtime.getTypeId(keys_obj);
    const allocator = runtime.c_allocator;

    var values = std.ArrayList(*runtime.PyObject).init(allocator);
    defer values.deinit();

    if (keys_type == .list) {
        const list_obj: *runtime.PyListObject = @ptrCast(@alignCast(keys_obj));
        const items_ptr = list_obj.ob_item orelse return null;
        const list_size: usize = @intCast(list_obj.ob_size);

        for (items_ptr[0..list_size]) |key_obj| {
            const key_type = runtime.getTypeId(key_obj);
            if (key_type != .string) {
                return null;
            }

            const key_str = runtime.PyString.getValue(key_obj);

            if (runtime.PyDict.get(map_obj, key_str)) |value| {
                values.append(value) catch return null;
            } else {
                return null;
            }
        }
    } else if (keys_type == .tuple) {
        const tuple_obj: *runtime.PyTupleObject = @ptrCast(@alignCast(keys_obj));
        const items_ptr = tuple_obj.ob_item orelse return null;
        const tuple_size: usize = @intCast(tuple_obj.ob_size);

        for (items_ptr[0..tuple_size]) |key_obj| {
            const key_type = runtime.getTypeId(key_obj);
            if (key_type != .string) {
                return null;
            }

            const key_str = runtime.PyString.getValue(key_obj);

            if (runtime.PyDict.get(map_obj, key_str)) |value| {
                values.append(value) catch return null;
            } else {
                return null;
            }
        }
    } else {
        return null;
    }

    const result = runtime.PyTuple.create(allocator, values.items) catch return null;
    return @ptrCast(result);
}

/// Match class for pattern matching
pub fn matchClass(
    subject: ?*anyopaque,
    type_: ?*anyopaque,
    nargs: usize,
    kwargs: ?*anyopaque,
) ?*anyopaque {
    const subject_ptr = subject orelse return null;
    const type_ptr = type_ orelse return null;

    const subject_obj: *runtime.PyObject = @ptrCast(@alignCast(subject_ptr));
    const type_obj: *runtime.PyObject = @ptrCast(@alignCast(type_ptr));
    const allocator = runtime.c_allocator;

    const subject_type = subject_obj.ob_type orelse return null;
    const match_type = type_obj.ob_type orelse return null;

    if (subject_type != match_type and !runtime.isSubclass(subject_type, match_type)) {
        return null;
    }

    var matched_values = std.ArrayList(*runtime.PyObject).init(allocator);
    defer matched_values.deinit();

    if (nargs > 0) {
        if (@hasField(@TypeOf(subject_obj.*), "__match_args__")) {
            // Handle positional matches via __match_args__
        }
    }

    if (kwargs) |kwargs_ptr| {
        const kwargs_obj: *runtime.PyObject = @ptrCast(@alignCast(kwargs_ptr));
        const kwargs_type = runtime.getTypeId(kwargs_obj);

        if (kwargs_type == .dict) {
            // Handle keyword matches
        }
    }
    _ = kwargs;

    const result = runtime.PyTuple.create(allocator, matched_values.items) catch return null;
    return @ptrCast(result);
}
