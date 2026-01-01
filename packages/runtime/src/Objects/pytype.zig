/// PyType - Runtime type object for metaclass support
/// Represents Python's `type` and dynamically created classes
const std = @import("std");
const hashmap_helper = @import("utils.hashmap_helper");
const PyValue = @import("object.zig").PyValue;

/// Runtime representation of a Python type/class
/// Used for:
/// - Metaclasses (classes inheriting from `type`)
/// - Dynamically created classes via `type(name, bases, dict)`
/// - Class objects that need runtime attribute manipulation
pub const PyType = struct {
    /// Class name (e.g., "MyClass")
    name: []const u8,

    /// Base classes (for MRO calculation)
    bases: []const *PyType,

    /// Class namespace dictionary (methods, attributes)
    dict: hashmap_helper.StringHashMap(PyValue),

    /// Method Resolution Order (computed from bases)
    mro: []const *PyType,

    /// The metaclass of this type (usually `type` itself)
    metaclass: ?*PyType,

    /// Allocator used for this type
    allocator: std.mem.Allocator,

    /// Create a new type object
    /// Equivalent to: type.__new__(metaclass, name, bases, dict)
    pub fn create(
        allocator: std.mem.Allocator,
        name: []const u8,
        bases: []const *PyType,
        dict: hashmap_helper.StringHashMap(PyValue),
    ) !*PyType {
        const self = try allocator.create(PyType);

        // Copy name
        const name_copy = try allocator.dupe(u8, name);

        // Copy bases array
        const bases_copy = try allocator.dupe(*PyType, bases);

        // Calculate MRO using C3 linearization
        const mro = try calculateMRO(allocator, self, bases_copy);

        self.* = .{
            .name = name_copy,
            .bases = bases_copy,
            .dict = dict,
            .mro = mro,
            .metaclass = null, // Set by caller if needed
            .allocator = allocator,
        };

        return self;
    }

    /// Create a type with a dict from key-value pairs
    pub fn createWithDict(
        allocator: std.mem.Allocator,
        name: []const u8,
        bases: []const *PyType,
        dict_items: anytype,
    ) !*PyType {
        var dict = hashmap_helper.StringHashMap(PyValue).init(allocator);

        // Add items from the input
        inline for (std.meta.fields(@TypeOf(dict_items))) |field| {
            const key = field.name;
            const value = @field(dict_items, field.name);
            try dict.put(key, PyValue.from(value));
        }

        return create(allocator, name, bases, dict);
    }

    /// Get an attribute from this type
    pub fn getattr(self: *const PyType, name: []const u8) ?PyValue {
        // First check our own dict
        if (self.dict.get(name)) |value| {
            return value;
        }

        // Then check MRO (base classes)
        for (self.mro) |base| {
            if (base != self) {
                if (base.dict.get(name)) |value| {
                    return value;
                }
            }
        }

        return null;
    }

    /// Set an attribute on this type
    pub fn setattr(self: *PyType, name: []const u8, value: PyValue) !void {
        try self.dict.put(name, value);
    }

    /// Delete an attribute from this type
    pub fn delattr(self: *PyType, name: []const u8) bool {
        return self.dict.swapRemove(name);
    }

    /// Check if type has an attribute
    pub fn hasattr(self: *const PyType, name: []const u8) bool {
        return self.getattr(name) != null;
    }

    /// Call this type to create an instance
    /// Equivalent to: MyClass(args...)
    pub fn call(self: *PyType, allocator: std.mem.Allocator, args: anytype) !PyValue {
        _ = allocator; // Will be used for instance creation
        _ = args; // Will be used for __init__ args

        // Look for __call__ in metaclass chain
        if (self.metaclass) |meta| {
            if (meta.getattr("__call__")) |call_method| {
                _ = call_method;
                // TODO: Invoke __call__ method
            }
        }

        // Default behavior: create instance and call __init__
        // For now, return a PyValue wrapping self
        return PyValue{ .type_obj = self };
    }

    /// Get the type's name
    pub fn getName(self: *const PyType) []const u8 {
        return self.name;
    }

    /// Get the type's bases
    pub fn getBases(self: *const PyType) []const *PyType {
        return self.bases;
    }

    /// Get the type's MRO
    pub fn getMRO(self: *const PyType) []const *PyType {
        return self.mro;
    }

    /// Free the type object
    pub fn deinit(self: *PyType) void {
        self.dict.deinit(self.allocator);
        self.allocator.free(self.name);
        self.allocator.free(self.bases);
        self.allocator.free(self.mro);
        self.allocator.destroy(self);
    }
};

/// The builtin `type` type object (singleton)
/// Represents Python's `type` metaclass
pub var builtin_type: ?*PyType = null;

/// Initialize the builtin type object
pub fn initBuiltinType(allocator: std.mem.Allocator) !*PyType {
    if (builtin_type) |t| return t;

    const dict = hashmap_helper.StringHashMap(PyValue).init(allocator);
    const t = try allocator.create(PyType);
    t.* = .{
        .name = "type",
        .bases = &[_]*PyType{},
        .dict = dict,
        .mro = &[_]*PyType{t}, // type's MRO is just itself
        .metaclass = t, // type is its own metaclass
        .allocator = allocator,
    };
    builtin_type = t;
    return t;
}

/// Get the builtin type object
pub fn getBuiltinType() ?*PyType {
    return builtin_type;
}

/// Calculate MRO using C3 linearization algorithm
/// https://www.python.org/download/releases/2.3/mro/
fn calculateMRO(allocator: std.mem.Allocator, cls: *PyType, bases: []const *PyType) ![]const *PyType {
    var result: std.ArrayList(*PyType) = .{};

    // Start with the class itself
    try result.append(allocator, cls);

    // Simple case: no bases
    if (bases.len == 0) {
        return result.toOwnedSlice(allocator);
    }

    // For single inheritance, just prepend to parent's MRO
    if (bases.len == 1) {
        for (bases[0].mro) |base| {
            try result.append(allocator, base);
        }
        return result.toOwnedSlice(allocator);
    }

    // Multiple inheritance: C3 linearization
    // This is a simplified version - full C3 is more complex
    var seen = std.AutoHashMap(*PyType, void).init(allocator);
    defer seen.deinit();

    try seen.put(cls, {});

    for (bases) |base| {
        for (base.mro) |mro_cls| {
            if (!seen.contains(mro_cls)) {
                try result.append(allocator, mro_cls);
                try seen.put(mro_cls, {});
            }
        }
    }

    return result.toOwnedSlice(allocator);
}

/// type.__new__(cls, name, bases, dict) - Create a new class
pub fn typeNew(
    allocator: std.mem.Allocator,
    metaclass: *PyType,
    name: []const u8,
    bases: []const *PyType,
    dict: hashmap_helper.StringHashMap(PyValue),
) !*PyType {
    const new_type = try PyType.create(allocator, name, bases, dict);
    new_type.metaclass = metaclass;

    // Call metaclass.__init__ if it exists
    if (metaclass.getattr("__init__")) |init_method| {
        _ = init_method;
        // TODO: Call __init__(new_type, name, bases, dict)
    }

    return new_type;
}

/// type(obj) - Get type of object (single arg form)
/// type(name, bases, dict) - Create new type (three arg form)
pub fn typeCall(allocator: std.mem.Allocator, args: anytype) !PyValue {
    const ArgsType = @TypeOf(args);
    const args_len = std.meta.fields(ArgsType).len;

    if (args_len == 1) {
        // type(obj) - return type of object
        // For now, just return a type name as string
        return PyValue{ .string = @typeName(ArgsType) };
    } else if (args_len == 3) {
        // type(name, bases, dict) - create new type
        const name = args[0];
        const bases = args[1];
        const dict = args[2];

        _ = bases;
        _ = dict;

        const t = try initBuiltinType(allocator);
        const empty_dict = hashmap_helper.StringHashMap(PyValue).init(allocator);
        const new_type = try typeNew(allocator, t, name, &[_]*PyType{}, empty_dict);
        return PyValue{ .type_obj = new_type };
    }

    return error.TypeError;
}

/// Dynamic class creation: type(name, bases, dict)
/// This is the codegen-facing API for the 3-arg type() builtin
/// Handles conversion from Python/Zig types to PyType
pub fn dynamicType(allocator: std.mem.Allocator, name: anytype, bases: anytype, dict: anytype) !*PyType {
    // Convert name to string
    const name_str: []const u8 = blk: {
        const NameType = @TypeOf(name);
        if (NameType == []const u8 or NameType == []u8) {
            break :blk name;
        } else if (@typeInfo(NameType) == .pointer) {
            const ptr_info = @typeInfo(NameType).pointer;
            if (ptr_info.child == u8 and ptr_info.sentinel() != null) {
                break :blk std.mem.span(name);
            }
            if (@typeInfo(ptr_info.child) == .array) {
                const arr_info = @typeInfo(ptr_info.child).array;
                if (arr_info.child == u8) {
                    break :blk name[0..arr_info.len];
                }
            }
        }
        break :blk "";
    };

    // For now, ignore bases and dict - just create a simple type
    // TODO: Convert bases tuple to []const *PyType
    // TODO: Convert dict to StringHashMap(PyValue)
    _ = bases;
    _ = dict;

    const t = try initBuiltinType(allocator);
    const empty_dict = hashmap_helper.StringHashMap(PyValue).init(allocator);
    return typeNew(allocator, t, name_str, &[_]*PyType{}, empty_dict);
}
