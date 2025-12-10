/// Dynamic attribute and scope access for AOT-compiled Python
/// In AOT compilation, we can't use runtime reflection like CPython.
/// Instead, we use hashmaps keyed by object address for dynamic attributes.
const std = @import("std");
const hashmap_helper = @import("utils.hashmap_helper");

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

/// Placeholder for PyObject - can hold any object for dynamic access
pub const PyObject = struct {
    ptr: *anyopaque,
    type_id: usize = 0,
};

/// Placeholder for PyDict - use hashmap
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
        const result = attrs.getOrPut(allocator, obj_id) catch return;
        if (!result.found_existing) {
            result.value_ptr.* = hashmap_helper.StringHashMap(PyValue).init(allocator);
        }
        result.value_ptr.put(allocator, name, value) catch return;
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
