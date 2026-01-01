/// Python type operations
/// istype, isCallable, isSubclass, isSubclassMulti
/// Extracted from runtime.zig to reduce file size
const std = @import("std");

// Import PyTypeObject from parent module via pyobject
const pyobject = @import("pyobject.zig");
const PyTypeObject = pyobject.PyTypeObject;

// Import numbers ABC for numeric hierarchy checks
const numbers_abc = @import("numbers_abc.zig");
pub const NumbersABC = numbers_abc.NumbersABC;
const type_predicates = @import("type_predicates.zig");

// ============================================================================
// Global ABC Registry for Virtual Subclasses
// ============================================================================
// Implements Python's ABCMeta.register() functionality
// When B.register(V) is called, V becomes a "virtual subclass" of B
// issubclass(V, B) returns True, but V is NOT in B's MRO

/// Maximum number of virtual subclass registrations
const MAX_ABC_REGISTRATIONS = 64;

/// A single virtual subclass registration: subclass_name is a virtual subclass of base_name
const ABCRegistration = struct {
    base_name: []const u8,
    subclass_name: []const u8,
};

/// Global storage for ABC registrations
var abc_registry: [MAX_ABC_REGISTRATIONS]ABCRegistration = undefined;
var abc_registry_count: usize = 0;

/// Register a virtual subclass: makes issubclass(subclass, base) return True
/// Called by B.register(V) in generated code
pub fn registerVirtualSubclass(base_name: []const u8, subclass_name: []const u8) void {
    if (abc_registry_count >= MAX_ABC_REGISTRATIONS) {
        // Registry full - silently ignore (matches CPython behavior of no error)
        return;
    }
    // Check if already registered
    for (abc_registry[0..abc_registry_count]) |reg| {
        if (std.mem.eql(u8, reg.base_name, base_name) and
            std.mem.eql(u8, reg.subclass_name, subclass_name))
        {
            return; // Already registered
        }
    }
    abc_registry[abc_registry_count] = .{
        .base_name = base_name,
        .subclass_name = subclass_name,
    };
    abc_registry_count += 1;
}

/// Check if subclass_name is a registered virtual subclass of base_name
pub fn isVirtualSubclass(subclass_name: []const u8, base_name: []const u8) bool {
    for (abc_registry[0..abc_registry_count]) |reg| {
        if (std.mem.eql(u8, reg.base_name, base_name) and
            std.mem.eql(u8, reg.subclass_name, subclass_name))
        {
            return true;
        }
    }
    return false;
}

/// Check if subclass_type is a virtual subclass of base_type using __name__ declarations
pub fn isVirtualSubclassType(comptime SubType: type, comptime BaseType: type) bool {
    // Get class names from __name__ declarations
    const sub_name = if (@hasDecl(SubType, "__name__")) SubType.__name__ else return false;
    const base_name = if (@hasDecl(BaseType, "__name__")) BaseType.__name__ else return false;
    return isVirtualSubclass(sub_name, base_name);
}

/// Clear all virtual subclass registrations for a specific base class
/// Called by ABCMeta class's _abc_registry_clear() method
pub fn clearRegistryForClass(class_name: []const u8) void {
    // Compact the registry by removing entries for this class
    var write_idx: usize = 0;
    for (abc_registry[0..abc_registry_count]) |reg| {
        if (!std.mem.eql(u8, reg.base_name, class_name)) {
            // Keep entries for other classes
            abc_registry[write_idx] = reg;
            write_idx += 1;
        }
    }
    abc_registry_count = write_idx;
}

/// Get count of virtual subclasses registered for a class (for debugging/testing)
pub fn getRegistryCountForClass(class_name: []const u8) usize {
    var count: usize = 0;
    for (abc_registry[0..abc_registry_count]) |reg| {
        if (std.mem.eql(u8, reg.base_name, class_name)) {
            count += 1;
        }
    }
    return count;
}

/// Comptime type check for Python type names
/// Used for comptime branching in type-checking patterns with anytype params
/// Example: if (comptime !runtime.istype(@TypeOf(x), "int")) return error.TypeError;
pub fn istype(comptime T: type, comptime type_name: []const u8) bool {
    const info = @typeInfo(T);

    if (comptime std.mem.eql(u8, type_name, "int")) {
        return type_predicates.isIntInfo(info) or T == bool;
    } else if (comptime std.mem.eql(u8, type_name, "float")) {
        return type_predicates.isFloatInfo(info);
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
/// Also checks ABC registry for virtual subclasses (ABCMeta.register)
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

    // For Zig struct types (compile-time classes), check:
    // 1. Direct type equality
    // 2. __bases_vtables__ chain (regular inheritance)
    // 3. ABC registry (virtual subclasses via ABCMeta.register)
    if (@typeInfo(ClsType) == .type and @typeInfo(BaseType) == .type) {
        // Same type
        if (cls == base) return true;

        // Only check @hasDecl for struct types (not primitives like i64)
        const cls_info = @typeInfo(cls);
        const base_info = @typeInfo(base);
        const cls_is_struct = cls_info == .@"struct" or cls_info == .@"union" or cls_info == .@"enum";
        const base_is_struct = base_info == .@"struct" or base_info == .@"union" or base_info == .@"enum";

        if (cls_is_struct and base_is_struct) {
            // Check __bases_vtables__ for regular inheritance
            if (@hasDecl(cls, "__bases_vtables__") and @hasDecl(base, "__vtable__")) {
                const bases = cls.__bases_vtables__;
                const base_vtable = &base.__vtable__;
                for (bases) |b| {
                    if (b == base_vtable) return true;
                }
            }

            // Check ABC registry for virtual subclasses
            if (@hasDecl(cls, "__name__") and @hasDecl(base, "__name__")) {
                if (isVirtualSubclass(cls.__name__, base.__name__)) {
                    return true;
                }
            }
        }

        return false;
    }

    // For runtime values that are type objects, compare directly
    // This handles cases where types are passed as runtime values
    // But only if they're the same type - otherwise we can't compare
    if (ClsType == BaseType) {
        return cls == base;
    }

    // Handle Zig primitive types against null ABC pointers
    // When base is ?*anyopaque = null (imported ABC like Integral, Real, etc.),
    // and cls is a Zig type, check the Python numbers hierarchy
    // NOTE: This case shouldn't be reached - codegen should use isBuiltinSubclassOfNumbersABC
    // for checks against ABC types. But we handle it defensively here.
    if (@typeInfo(ClsType) == .type and BaseType == ?*anyopaque) {
        // base is null - we can't determine which ABC it represents at runtime
        // This path is reached when codegen generates: isSubclass(i64, Integral)
        // where Integral is defined as: const Integral: ?*anyopaque = null;
        // Since we can't distinguish which ABC null represents, return false.
        // The fix needs to be in codegen to use isBuiltinSubclassOfNumbersABC.
        return false;
    }

    // Incompatible types can't be subclasses
    return false;
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

// ============================================================================
// Numbers ABC Support (issubclass with numbers.Number, etc.)
// ============================================================================

/// Check if a type (by name) is a subclass of a numbers ABC
/// Used by codegen for: issubclass(int, numbers.Number)
///
/// Examples:
///   isNumbersSubclass("int", .Number) -> true
///   isNumbersSubclass("float", .Integral) -> false
///   isNumbersSubclass("Decimal", .Number) -> true
pub fn isNumbersSubclass(type_name: []const u8, abc: NumbersABC) bool {
    return numbers_abc.isBuiltinSubclassOfABC(type_name, abc);
}

/// Check if a comptime type is a subclass of a numbers ABC
/// Uses __class_name__ or Zig type introspection to determine the type name
pub fn isNumbersSubclassType(comptime T: type, abc: NumbersABC) bool {
    const info = @typeInfo(T);

    // Check for __class_name__ on structs (user-defined classes like Decimal, Fraction)
    if (info == .@"struct" and @hasDecl(T, "__class_name__")) {
        return numbers_abc.isBuiltinSubclassOfABC(T.__class_name__, abc);
    }

    // Built-in types
    if (T == bool) {
        return numbers_abc.isBuiltinSubclassOfABC("bool", abc);
    }
    if (type_predicates.isIntInfo(info)) {
        return numbers_abc.isBuiltinSubclassOfABC("int", abc);
    }
    if (type_predicates.isFloatInfo(info)) {
        return numbers_abc.isBuiltinSubclassOfABC("float", abc);
    }

    return false;
}

/// Parse a numbers ABC name string to enum (for codegen)
pub fn parseNumbersABC(name: []const u8) ?NumbersABC {
    return numbers_abc.parseABCName(name);
}
