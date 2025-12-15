/// Python type operations
/// istype, isCallable, isSubclass, isSubclassMulti
/// Extracted from runtime.zig to reduce file size
const std = @import("std");

// Import PyTypeObject from parent module via pyobject
const pyobject = @import("pyobject.zig");
const PyTypeObject = pyobject.PyTypeObject;

/// Comptime type check for Python type names
/// Used for comptime branching in type-checking patterns with anytype params
/// Example: if (comptime !runtime.istype(@TypeOf(x), "int")) return error.TypeError;
pub fn istype(comptime T: type, comptime type_name: []const u8) bool {
    const info = @typeInfo(T);

    if (comptime std.mem.eql(u8, type_name, "int")) {
        return info == .int or info == .comptime_int or T == bool;
    } else if (comptime std.mem.eql(u8, type_name, "float")) {
        return info == .float or info == .comptime_float;
    } else if (comptime std.mem.eql(u8, type_name, "bool")) {
        return T == bool;
    } else if (comptime std.mem.eql(u8, type_name, "str")) {
        if (T == []const u8 or T == []u8) return true;
        // String literals: *const [N:0]u8
        if (info == .pointer and info.pointer.size == .one) {
            const child_info = @typeInfo(info.pointer.child);
            if (child_info == .array and child_info.array.child == u8) {
                return true;
            }
        }
        return false;
    } else {
        // Unknown type - check for struct with matching name
        if (info == .@"struct") {
            if (@hasDecl(T, "__class_name__")) {
                return std.mem.eql(u8, T.__class_name__, type_name);
            }
        }
        return false;
    }
}

/// Check if a value is callable (has a __call__ method or is a function)
pub fn isCallable(value: anytype) bool {
    const T = @TypeOf(value);
    const info = @typeInfo(T);
    return switch (info) {
        .@"fn" => true,
        .pointer => |ptr| switch (@typeInfo(ptr.child)) {
            .@"fn" => true,
            .@"struct" => @hasDecl(ptr.child, "__call__"),
            else => false,
        },
        .@"struct" => @hasDecl(T, "__call__"),
        else => false,
    };
}

/// Check if cls is a subclass of base
/// For PyTypeObject pointers, checks the type hierarchy via tp_base chain
pub fn isSubclass(cls: anytype, base: anytype) bool {
    const ClsType = @TypeOf(cls);
    const BaseType = @TypeOf(base);

    // Handle PyTypeObject pointer comparison (runtime type objects)
    if (ClsType == *PyTypeObject and BaseType == *PyTypeObject) {
        // Same type is always a subclass of itself
        if (cls == base) return true;

        // Walk the tp_base chain
        var current: ?*PyTypeObject = cls.tp_base;
        while (current) |cur| {
            if (cur == base) return true;
            current = cur.tp_base;
        }
        return false;
    }

    // Handle const pointer to PyTypeObject
    if (ClsType == *const PyTypeObject and BaseType == *const PyTypeObject) {
        if (cls == base) return true;
        var current: ?*const PyTypeObject = cls.tp_base;
        while (current) |cur| {
            if (cur == base) return true;
            current = cur.tp_base;
        }
        return false;
    }

    // For runtime values that are type objects, compare directly
    // This handles cases where types are passed as runtime values
    return cls == base;
}

/// Check if cls is a subclass of any of the types in the tuple
pub fn isSubclassMulti(cls: anytype, bases: anytype) bool {
    const BasesType = @TypeOf(bases);

    // Handle slice of PyTypeObject pointers
    if (BasesType == []*PyTypeObject or BasesType == []const *PyTypeObject or
        BasesType == []*const PyTypeObject or BasesType == []const *const PyTypeObject)
    {
        for (bases) |base| {
            if (isSubclass(cls, base)) return true;
        }
        return false;
    }

    // Single base - delegate to isSubclass
    return isSubclass(cls, bases);
}

/// Safely extract element type from arrays/slices without indexing
/// This handles empty arrays which would fail with @TypeOf(array[0])
/// Used for: stub module imports that may be empty arrays
///
/// Example:
/// ```
/// const arr: []const []const u8 = &[_][]const u8{};
/// const ElemType = ElementType(@TypeOf(arr)); // []const u8, not compile error
/// ```
pub fn ElementType(comptime T: type) type {
    const info = @typeInfo(T);

    // Handle slices: []T -> T
    if (info == .pointer and info.pointer.size == .slice) {
        return info.pointer.child;
    }

    // Handle arrays: [N]T -> T
    if (info == .array) {
        return info.array.child;
    }

    // Handle pointer to array: *[N]T -> T
    if (info == .pointer and info.pointer.size == .one) {
        const child_info = @typeInfo(info.pointer.child);
        if (child_info == .array) {
            return child_info.array.child;
        }
    }

    // Handle ArrayListUnmanaged: has .items field
    if (info == .@"struct" and @hasField(T, "items")) {
        const items_type = @TypeOf(@as(T, undefined).items);
        const items_info = @typeInfo(items_type);
        if (items_info == .pointer and items_info.pointer.size == .slice) {
            return items_info.pointer.child;
        }
    }

    // Fallback: return the type itself (can't extract element)
    return T;
}

/// Check if a type is iterable (has element type that can be extracted)
pub fn isIterable(comptime T: type) bool {
    const info = @typeInfo(T);
    return (info == .pointer and info.pointer.size == .slice) or
        info == .array or
        (info == .pointer and info.pointer.size == .one and @typeInfo(info.pointer.child) == .array) or
        (info == .@"struct" and @hasField(T, "items"));
}
