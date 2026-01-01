/// Dynamic attribute and scope access for AOT-compiled Python
/// In AOT compilation, we can't use runtime reflection like CPython.
/// Instead, we use hashmaps keyed by object address for dynamic attributes.
const std = @import("std");
const hashmap_helper = @import("utils.hashmap_helper");
const type_predicates = @import("type_predicates.zig");

/// PyValue represents any Python value at runtime
pub const PyValue = union(enum) {
    none,
    int: i64,
    float: f64,
    string: []const u8,
    boolean: bool,
    object: *anyopaque,
};

/// Storage for dynamic attributes indexed by object pointer
var dynamic_attrs: ?hashmap_helper.HashMap(usize, hashmap_helper.StringHashMap(PyValue)) = null;
var attr_allocator: ?std.mem.Allocator = null;

/// Initialize the dynamic attribute storage
pub fn initDynamicAttrs(allocator: std.mem.Allocator) void {
    attr_allocator = allocator;
    dynamic_attrs = hashmap_helper.HashMap(usize, hashmap_helper.StringHashMap(PyValue)).init(allocator);
}

/// Generic object wrapper for dynamic attribute access
pub const PyObject = struct {
    ptr: *anyopaque,
    type_id: usize = 0,
};

/// Dictionary type for dynamic scope storage
pub const PyDict = hashmap_helper.StringHashMap(PyValue);

/// Get attribute from object (dynamic attribute access)
/// First checks static type info, then falls back to dynamic attrs store
pub fn getattr_builtin(obj: *PyObject, name: []const u8) ?PyValue {
    // Check dynamic attributes store
    if (dynamic_attrs) |*attrs| {
        const obj_id = @intFromPtr(obj.ptr);
        if (attrs.get(obj_id)) |obj_attrs| {
            if (obj_attrs.get(name)) |value| {
                return value;
            }
        }
    }
    // Attribute not found
    return null;
}

/// Set attribute on object (dynamic attribute access)
pub fn setattr_builtin(obj: *PyObject, name: []const u8, value: PyValue) void {
    const allocator = attr_allocator orelse return;
    if (dynamic_attrs == null) {
        initDynamicAttrs(allocator);
    }

    const obj_id = @intFromPtr(obj.ptr);

    // Get or create attribute map for this object
    if (dynamic_attrs) |*attrs| {
        const result = attrs.getOrPut(allocator, obj_id) catch unreachable;
        if (!result.found_existing) {
            result.value_ptr.* = hashmap_helper.StringHashMap(PyValue).init(allocator);
        }
        result.value_ptr.put(allocator, name, value) catch unreachable;
    }
}

/// Delete attribute from object
pub fn delattr_builtin(obj: *PyObject, name: []const u8) bool {
    if (dynamic_attrs) |*attrs| {
        const obj_id = @intFromPtr(obj.ptr);
        if (attrs.getPtr(obj_id)) |obj_attrs| {
            return obj_attrs.remove(name);
        }
    }
    return false;
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

/// Thread-local storage for global and local scopes
threadlocal var global_scope: ?*PyDict = null;
threadlocal var local_scope: ?*PyDict = null;

/// Set the global scope for this thread
pub fn setGlobalScope(scope: *PyDict) void {
    global_scope = scope;
}

/// Set the local scope for this thread
pub fn setLocalScope(scope: *PyDict) void {
    local_scope = scope;
}

/// Get the __dict__ of an object, or create one if it doesn't exist
pub fn vars_builtin(obj: ?*PyObject) ?*PyDict {
    const allocator = attr_allocator orelse return null;

    if (obj) |o| {
        // Return the dynamic attributes for this object
        if (dynamic_attrs == null) {
            initDynamicAttrs(allocator);
        }

        if (dynamic_attrs) |*attrs| {
            const obj_id = @intFromPtr(o.ptr);
            const result = attrs.getOrPut(allocator, obj_id) catch return null;
            if (!result.found_existing) {
                result.value_ptr.* = hashmap_helper.StringHashMap(PyValue).init(allocator);
            }
            return result.value_ptr;
        }
    } else {
        // No object provided - return local scope
        return local_scope;
    }
    return null;
}

/// Get the global namespace dictionary
pub fn globals_builtin() ?*PyDict {
    return global_scope;
}

/// Get the local namespace dictionary
pub fn locals_builtin() ?*PyDict {
    return local_scope;
}

/// Global scope registry for dir() with no arguments
/// Tracks names that have been added to the current scope
const ScopeRegistry = struct {
    var names: [256][]const u8 = [_][]const u8{""} ** 256;
    var count: usize = 0;

    /// Register a name in the current scope
    pub fn register(name: []const u8) void {
        if (count < names.len) {
            names[count] = name;
            count += 1;
        }
    }

    /// Get all registered names
    pub fn getNames() []const []const u8 {
        return names[0..count];
    }

    /// Clear the registry
    pub fn clear() void {
        count = 0;
    }
};

/// Register a variable in the current scope (called during variable assignment)
pub fn registerScopeVar(name: []const u8) void {
    ScopeRegistry.register(name);
}

/// Clear scope variables (called on scope exit)
pub fn clearScopeVars() void {
    ScopeRegistry.clear();
}

/// Returns a list of names in the current local scope (if obj is null)
/// or a list of valid attributes for the object (if obj is provided)
pub fn dir_builtin(obj: anytype) []const []const u8 {
    const T = @TypeOf(obj);

    // If obj is null, return names from the scope registry
    if (T == @TypeOf(null)) {
        return ScopeRegistry.getNames();
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

/// Generic struct attribute access using comptime reflection
/// Works with any struct type (staticmethod, classmethod, custom classes, etc.)
/// Returns the field value wrapped in a PyValue if found, null otherwise
pub fn structGetattr(obj: anytype, name: []const u8) ?@import("../Objects/object.zig").PyValue {
    const T = @TypeOf(obj);
    const info = @typeInfo(T);

    // Handle pointers - dereference
    if (info == .pointer) {
        const Child = info.pointer.child;
        const child_info = @typeInfo(Child);
        if (child_info == .@"struct") {
            return structGetattrImpl(Child, obj.*, name);
        }
        return null;
    }

    // Handle structs directly
    if (info == .@"struct") {
        return structGetattrImpl(T, obj, name);
    }

    return null;
}

fn structGetattrImpl(comptime T: type, obj: T, name: []const u8) ?@import("../Objects/object.zig").PyValue {
    const PyValueObj = @import("../Objects/object.zig").PyValue;
    const ObjectInstance = PyValueObj.ObjectInstance;
    const fields = @typeInfo(T).@"struct".fields;

    // Use inline for to iterate fields at comptime
    inline for (fields) |field| {
        if (std.mem.eql(u8, field.name, name)) {
            const value = @field(obj, field.name);
            // Convert to PyValue based on type
            const FieldT = @TypeOf(value);
            const field_info = @typeInfo(FieldT);

            if (FieldT == []const u8) {
                return PyValueObj{ .string = value };
            } else if (FieldT == ?[]const u8) {
                if (value) |v| {
                    return PyValueObj{ .string = v };
                }
                return PyValueObj.none;
            } else if (type_predicates.isIntInfo(field_info)) {
                return PyValueObj{ .int = @intCast(value) };
            } else if (type_predicates.isFloatInfo(field_info)) {
                return PyValueObj{ .float = @floatCast(value) };
            } else if (FieldT == bool) {
                return PyValueObj{ .boolean = value };
            } else if (FieldT == PyValueObj) {
                return value;
            } else if (FieldT == ObjectInstance) {
                // ObjectInstance is already a class instance wrapper
                return PyValueObj{ .class_instance = value };
            } else if (field_info == .pointer) {
                // Pointer types can be wrapped directly
                return PyValueObj{ .object = @ptrCast(@constCast(value)) };
            } else {
                // For non-pointer types, return none (can't safely wrap)
                return PyValueObj.none;
            }
        }
    }

    return null;
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

/// Dynamic attribute access for anytype parameters
/// Handles primitives (i64, f64) with synthetic real/imag, and structs with field/method dispatch
pub fn getAttrDynamic(obj: anytype, comptime name: []const u8) f64 {
    const T = @TypeOf(obj);
    const info = @typeInfo(T);

    // For primitives, handle synthetic "real" and "imag" attributes
    // (Python numeric protocol: int/float have .real/.imag properties)
    if (info == .int or info == .comptime_int) {
        if (comptime std.mem.eql(u8, name, "real")) {
            return @floatFromInt(obj);
        } else if (comptime std.mem.eql(u8, name, "imag")) {
            return 0.0;
        }
    }
    if (info == .float or info == .comptime_float) {
        if (comptime std.mem.eql(u8, name, "real")) {
            return @floatCast(obj);
        } else if (comptime std.mem.eql(u8, name, "imag")) {
            return 0.0;
        }
    }

    // For structs, check if it's a method or field
    if (info == .@"struct") {
        // First check for method (declaration)
        if (@hasDecl(T, name)) {
            const method = @field(T, name);
            // If it's a method, call it with obj as self
            if (@typeInfo(@TypeOf(method)) == .@"fn") {
                const result = @call(.auto, method, .{obj});
                return convertToF64(result);
            }
        }
        // Then check for field
        if (@hasField(T, name)) {
            const val = @field(obj, name);
            return convertToF64(val);
        }
    }

    // For pointers to structs, dereference and recurse
    if (info == .pointer and info.pointer.size == .one) {
        const Child = info.pointer.child;
        if (@typeInfo(Child) == .@"struct") {
            if (@hasDecl(Child, name)) {
                const method = @field(Child, name);
                if (@typeInfo(@TypeOf(method)) == .@"fn") {
                    // Methods expect *const @This(), so pass the pointer (obj) not dereferenced value
                    const result = @call(.auto, method, .{obj});
                    return convertToF64(result);
                }
            }
            if (@hasField(Child, name)) {
                const val = @field(obj.*, name);
                return convertToF64(val);
            }
        }
    }

    // Default: attribute not found, return 0
    return 0.0;
}

/// Convert various types to f64 for attribute return
fn convertToF64(val: anytype) f64 {
    const V = @TypeOf(val);
    const vinfo = @typeInfo(V);
    if (vinfo == .int or vinfo == .comptime_int) {
        return @floatFromInt(val);
    }
    if (vinfo == .float or vinfo == .comptime_float) {
        return @floatCast(val);
    }
    // Default
    return 0.0;
}
