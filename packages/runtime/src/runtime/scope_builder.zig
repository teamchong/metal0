/// ScopeBuilder - Helper to build PyDict scopes from Zig values
/// Used for eval(source, globals, locals) variable injection
const std = @import("std");
const runtime = @import("../runtime.zig");
const PyObject = runtime.PyObject;
const PyDict = @import("../Objects/dictobject.zig").PyDict;
const PyInt = @import("../Objects/intobject.zig").PyInt;
const PyFloat = @import("../Objects/floatobject.zig").PyFloat;
const PyString = @import("../Objects/stringlib/core.zig").PyString;
const PyBool = @import("../Objects/boolobject.zig").PyBool;

/// Builder for creating scope dictionaries
pub const ScopeBuilder = struct {
    dict: *PyObject,
    allocator: std.mem.Allocator,

    /// Create a new empty scope
    pub fn init(allocator: std.mem.Allocator) !ScopeBuilder {
        return .{
            .dict = try PyDict.create(allocator),
            .allocator = allocator,
        };
    }

    /// Get the built dict (transfers ownership)
    pub fn build(self: *ScopeBuilder) *PyObject {
        return self.dict;
    }

    /// Put a PyObject value
    pub fn put(self: *ScopeBuilder, name: []const u8, value: *PyObject) !void {
        try PyDict.set(self.dict, name, value);
    }

    /// Put an integer value
    pub fn putInt(self: *ScopeBuilder, name: []const u8, value: i64) !void {
        const obj = try PyInt.create(self.allocator, value);
        try PyDict.set(self.dict, name, obj);
    }

    /// Put a float value
    pub fn putFloat(self: *ScopeBuilder, name: []const u8, value: f64) !void {
        const obj = try PyFloat.create(self.allocator, value);
        try PyDict.set(self.dict, name, obj);
    }

    /// Put a string value
    pub fn putString(self: *ScopeBuilder, name: []const u8, value: []const u8) !void {
        const obj = try PyString.create(self.allocator, value);
        try PyDict.set(self.dict, name, obj);
    }

    /// Put a bool value
    pub fn putBool(self: *ScopeBuilder, name: []const u8, value: bool) !void {
        const obj = try PyBool.create(self.allocator, value);
        try PyDict.set(self.dict, name, obj);
    }

    /// Put None
    pub fn putNone(self: *ScopeBuilder, name: []const u8) !void {
        try PyDict.set(self.dict, name, runtime.Py_None);
    }
};

/// Convenience function to create a scope with a single variable
pub fn scopeWith(allocator: std.mem.Allocator, name: []const u8, value: *PyObject) !*PyObject {
    var builder = try ScopeBuilder.init(allocator);
    try builder.put(name, value);
    return builder.build();
}

/// Convenience function to create a scope with an integer
pub fn scopeWithInt(allocator: std.mem.Allocator, name: []const u8, value: i64) !*PyObject {
    var builder = try ScopeBuilder.init(allocator);
    try builder.putInt(name, value);
    return builder.build();
}

/// Convenience function to create a scope with a float
pub fn scopeWithFloat(allocator: std.mem.Allocator, name: []const u8, value: f64) !*PyObject {
    var builder = try ScopeBuilder.init(allocator);
    try builder.putFloat(name, value);
    return builder.build();
}
