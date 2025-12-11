/// Type builtin wrappers - simple functions that return a truthy []const u8
/// Used when types are stored as first-class values in lists
/// These return a non-empty string so bool(type) returns True

pub fn boolBuiltin(arg: []const u8) []const u8 {
    return if (arg.len > 0) arg else "bool";
}

pub fn intBuiltin(arg: []const u8) []const u8 {
    return if (arg.len > 0) arg else "int";
}

pub fn floatBuiltin(arg: []const u8) []const u8 {
    return if (arg.len > 0) arg else "float";
}

pub fn strBuiltin(arg: []const u8) []const u8 {
    return if (arg.len > 0) arg else "str";
}

pub fn bytesBuiltin(arg: []const u8) []const u8 {
    return if (arg.len > 0) arg else "bytes";
}

pub fn listBuiltin(arg: []const u8) []const u8 {
    return if (arg.len > 0) arg else "list";
}

pub fn dictBuiltin(arg: []const u8) []const u8 {
    return if (arg.len > 0) arg else "dict";
}

pub fn setBuiltin(arg: []const u8) []const u8 {
    return if (arg.len > 0) arg else "set";
}

pub fn tupleBuiltin(arg: []const u8) []const u8 {
    return if (arg.len > 0) arg else "tuple";
}

pub fn frozensetBuiltin(arg: []const u8) []const u8 {
    return if (arg.len > 0) arg else "frozenset";
}

pub fn typeBuiltin(arg: []const u8) []const u8 {
    return if (arg.len > 0) arg else "type";
}

pub fn objectBuiltin(arg: []const u8) []const u8 {
    return if (arg.len > 0) arg else "object";
}

pub fn complexBuiltin(arg: []const u8) []const u8 {
    return if (arg.len > 0) arg else "complex";
}

/// Call a type builtin with an argument and return the result
/// Used for: bool(x), int(x), str(x), etc.
pub fn boolBuiltinCall(t: anytype, args: anytype) !bool {
    _ = t;
    _ = args;
    // Type objects are always truthy
    return true;
}
