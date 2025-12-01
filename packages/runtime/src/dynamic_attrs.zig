/// Dynamic attribute and scope access runtime stubs
const std = @import("std");

/// Placeholder for PyObject - replace with actual type when available
pub const PyObject = struct {
    // Stub for MVP
};

/// Placeholder for PyDict - replace with actual type when available
pub const PyDict = struct {
    // Stub for MVP
};

pub fn getattr_builtin(obj: *PyObject, name: []const u8) *PyObject {
    _ = obj;
    _ = name;
    // For MVP: return placeholder
    @panic("getattr not implemented");
}

pub fn setattr_builtin(obj: *PyObject, name: []const u8, value: *PyObject) void {
    _ = obj;
    _ = name;
    _ = value;
    // For MVP: no-op
}

/// Check if an object has an attribute/method with the given name
/// Uses comptime reflection to check for declarations
pub fn hasattr_builtin(obj: anytype, name: []const u8) bool {
    const T = @TypeOf(obj);
    const info = @typeInfo(T);

    // For pointers, check the pointed-to type
    if (info == .pointer) {
        const Child = info.pointer.child;
        return hasattrType(Child, name);
    }

    // For direct types
    return hasattrType(T, name);
}

fn hasattrType(comptime T: type, name: []const u8) bool {
    const info = @typeInfo(T);

    // For structs, check declarations
    if (info == .@"struct") {
        // Check if it's an ArrayList - they have append, pop, etc.
        if (@hasDecl(T, "append")) {
            if (std.mem.eql(u8, name, "append")) return true;
        }
        if (@hasDecl(T, "pop")) {
            if (std.mem.eql(u8, name, "pop")) return true;
        }
        if (@hasDecl(T, "items")) {
            if (std.mem.eql(u8, name, "items") or
                std.mem.eql(u8, name, "__iter__") or
                std.mem.eql(u8, name, "__len__")) return true;
        }
        // Check for __dict__ field (custom classes)
        if (@hasField(T, "__dict__")) {
            // Custom class - check if it has the method declared
            inline for (@typeInfo(T).@"struct".decls) |decl| {
                if (std.mem.eql(u8, decl.name, name)) return true;
            }
        }
    }

    // String/slice types have string methods
    if (info == .pointer and info.pointer.size == .slice) {
        const string_methods = [_][]const u8{
            "upper",      "lower",    "strip",   "split",    "join",  "replace",
            "startswith", "endswith", "find",    "index",    "count", "encode",
            "decode",     "format",   "__len__", "__iter__",
        };
        for (string_methods) |method| {
            if (std.mem.eql(u8, name, method)) return true;
        }
    }

    return false;
}

pub fn vars_builtin(obj: ?*PyObject) *PyDict {
    _ = obj;
    // For MVP: return empty dict placeholder
    @panic("vars not implemented");
}

pub fn globals_builtin() *PyDict {
    // For MVP: return empty dict placeholder
    @panic("globals not implemented");
}

pub fn locals_builtin() *PyDict {
    // For MVP: return empty dict placeholder
    @panic("locals not implemented");
}
