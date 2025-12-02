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

/// Returns a list of names in the current local scope (if obj is null)
/// or a list of valid attributes for the object (if obj is provided)
pub fn dir_builtin(obj: anytype) []const []const u8 {
    const T = @TypeOf(obj);

    // If obj is null, return empty list (would need scope info for full implementation)
    if (T == @TypeOf(null)) {
        return &[_][]const u8{};
    }

    // For optional types, unwrap
    const info = @typeInfo(T);
    if (info == .optional) {
        if (obj) |inner| {
            return dir_builtin(inner);
        }
        return &[_][]const u8{};
    }

    // For pointers, get attributes of pointed-to type
    if (info == .pointer) {
        const Child = info.pointer.child;
        return getTypeAttrs(Child);
    }

    return getTypeAttrs(T);
}

fn getTypeAttrs(comptime T: type) []const []const u8 {
    const info = @typeInfo(T);

    if (info == .@"struct") {
        // Get all public declarations
        const decls = @typeInfo(T).@"struct".decls;
        const fields = @typeInfo(T).@"struct".fields;

        // Count total attributes
        const count = decls.len + fields.len;

        // Build array of attribute names at comptime
        comptime var attrs: [count][]const u8 = undefined;
        comptime var i = 0;

        // Add declarations (methods, constants)
        inline for (decls) |decl| {
            attrs[i] = decl.name;
            i += 1;
        }

        // Add fields
        inline for (fields) |field| {
            attrs[i] = field.name;
            i += 1;
        }

        return &attrs;
    }

    // For slices (strings), return string methods
    if (info == .pointer and info.pointer.size == .slice) {
        return &[_][]const u8{
            "__add__",    "__class__",   "__contains__", "__eq__",
            "__ge__",     "__getitem__", "__gt__",       "__hash__",
            "__iter__",   "__le__",      "__len__",      "__lt__",
            "__mul__",    "__ne__",      "__repr__",     "__str__",
            "capitalize", "casefold",    "center",       "count",
            "encode",     "endswith",    "expandtabs",   "find",
            "format",     "index",       "isalnum",      "isalpha",
            "isascii",    "isdecimal",   "isdigit",      "isidentifier",
            "islower",    "isnumeric",   "isprintable",  "isspace",
            "istitle",    "isupper",     "join",         "ljust",
            "lower",      "lstrip",      "partition",    "replace",
            "rfind",      "rindex",      "rjust",        "rpartition",
            "rsplit",     "rstrip",      "split",        "splitlines",
            "startswith", "strip",       "swapcase",     "title",
            "translate",  "upper",       "zfill",
        };
    }

    // Default: return empty list
    return &[_][]const u8{};
}
