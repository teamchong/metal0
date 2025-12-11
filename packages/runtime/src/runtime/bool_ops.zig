/// Boolean operations for Python truthiness semantics
/// Extracted from runtime.zig to reduce file size
const std = @import("std");

// Forward imports from parent runtime module - these will be resolved at compile time
const pystring = @import("../Objects/unicodeobject.zig");
const PyString = pystring.PyString;
const pyint = @import("../Objects/intobject.zig");
const PyInt = pyint.PyInt;
const pybool = @import("../Objects/boolobject.zig");
const PyBool = pybool.PyBool;
const pylist = @import("../Objects/listobject.zig");
const NativeList = pylist.NativeList;
const object_zig = @import("../Objects/object.zig");
const PyValue = object_zig.PyValue;
const exceptions = @import("exceptions.zig");
const PythonError = exceptions.PythonError;

/// Generic bool conversion for Python truthiness semantics
/// Returns false for: 0, 0.0, false, empty strings, empty slices
/// Returns true for everything else
pub fn toBool(value: anytype) bool {
    const T = @TypeOf(value);
    const info = @typeInfo(T);

    // Handle integers
    if (info == .int or info == .comptime_int) {
        return value != 0;
    }

    // Handle floats
    if (info == .float or info == .comptime_float) {
        return value != 0.0;
    }

    // Handle bool
    if (T == bool) {
        return value;
    }

    // Handle slices (including strings)
    if (info == .pointer and info.pointer.size == .slice) {
        return value.len > 0;
    }

    // Handle single-item pointers to arrays (string literals)
    if (info == .pointer and info.pointer.size == .one) {
        const child_info = @typeInfo(info.pointer.child);
        if (child_info == .array) {
            return child_info.array.len > 0;
        }
        // Handle pointers to structs with __bool__ method (Python objects)
        if (child_info == .@"struct") {
            const ChildT = info.pointer.child;
            if (@hasDecl(ChildT, "__bool__")) {
                // Check if __bool__ takes a mutable pointer (self-mutating method)
                const bool_fn_info = @typeInfo(@TypeOf(ChildT.__bool__));
                const first_param_type = bool_fn_info.@"fn".params[0].type.?;
                const first_param_info = @typeInfo(first_param_type);

                const result = blk: {
                    if (first_param_info == .pointer and !first_param_info.pointer.is_const) {
                        // __bool__ takes *@This() (mutable) - value is already a pointer
                        if (info.pointer.is_const) {
                            // Cast away const if needed
                            break :blk @constCast(value).__bool__();
                        } else {
                            break :blk value.__bool__();
                        }
                    } else {
                        // __bool__ takes *const @This() or value - call directly
                        break :blk value.__bool__();
                    }
                };
                const ResultT = @TypeOf(result);
                if (@typeInfo(ResultT) == .bool) {
                    return result;
                }
                // Handle error union wrapping bool
                if (@typeInfo(ResultT) == .error_union) {
                    const unwrapped = result catch return false;
                    const UnwrappedT = @TypeOf(unwrapped);
                    if (@typeInfo(UnwrappedT) == .bool) {
                        return unwrapped;
                    }
                    @panic("TypeError: __bool__ should return bool, not error union with non-bool");
                }
                @panic("TypeError: __bool__ should return bool");
            }
            // Check for __len__ as fallback (containers with 0 length are falsy)
            if (@hasDecl(ChildT, "__len__")) {
                const len = value.__len__() catch return false;
                return len > 0;
            }
        }
    }

    // Handle PyString
    if (T == PyString) {
        return value.len() > 0;
    }

    // Handle PyInt
    if (T == PyInt) {
        return value.value != 0;
    }

    // Handle PyBool
    if (T == PyBool) {
        return value.value;
    }

    // Handle optional
    if (info == .optional) {
        return value != null;
    }

    // Handle structs with __bool__ method (Python protocol)
    if (info == .@"struct") {
        if (@hasDecl(T, "__bool__")) {
            // Check if __bool__ takes a mutable pointer (self-mutating method)
            const bool_fn_info = @typeInfo(@TypeOf(T.__bool__));
            const first_param_type = bool_fn_info.@"fn".params[0].type.?;
            const first_param_info = @typeInfo(first_param_type);

            const result = blk: {
                if (first_param_info == .pointer and !first_param_info.pointer.is_const) {
                    // __bool__ takes *@This() (mutable) - need to cast away const
                    // This matches Python's pass-by-reference semantics where
                    // objects can be mutated through any reference
                    var mutable = @constCast(&value);
                    break :blk mutable.__bool__();
                } else {
                    // __bool__ takes *const @This() or value - call directly
                    break :blk value.__bool__();
                }
            };
            const ResultT = @TypeOf(result);
            if (@typeInfo(ResultT) == .bool) {
                return result;
            }
            // Handle error union wrapping bool
            if (@typeInfo(ResultT) == .error_union) {
                const unwrapped = result catch return false;
                const UnwrappedT = @TypeOf(unwrapped);
                if (@typeInfo(UnwrappedT) == .bool) {
                    return unwrapped;
                }
                // __bool__ returned error union with non-bool payload
                @panic("TypeError: __bool__ should return bool, not error union with non-bool");
            }
            // Python 3: __bool__ MUST return bool (True or False)
            // Returning anything else (including int 0/1) is a TypeError
            @panic("TypeError: __bool__ should return bool");
        }
        // Check for __len__ as fallback (containers with 0 length are falsy)
        if (@hasDecl(T, "__len__")) {
            const len = value.__len__() catch return false;
            return len > 0;
        }
        // Check for NativeList first (has .items which is ArrayList, not slice)
        if (T == NativeList) {
            return value.items.items.len > 0;
        }
        // Check for .items field (ArrayListUnmanaged, etc.) - empty list is falsy
        if (@hasField(T, "items")) {
            return value.items.len > 0;
        }
        // Check for .count() method (HashMap/ArrayHashMap) - empty dict is falsy
        if (@hasDecl(T, "count")) {
            return value.count() > 0;
        }
    }

    // Handle arrays (fixed-size arrays) - empty is falsy, non-empty is truthy
    if (info == .array) {
        return info.array.len > 0;
    }

    // Handle tuples (anonymous structs with numbered fields) - empty tuple is falsy
    // This catches `struct {}` (empty tuple) and `struct { i64, i64 }` etc.
    if (info == .@"struct" and info.@"struct".is_tuple) {
        return info.@"struct".fields.len > 0;
    }

    // Default: truthy for everything else (non-empty types)
    return true;
}

/// Error-propagating version of toBool for use in contexts where __bool__ errors should propagate
/// This is used by pyOr/pyAnd which need to report __bool__ errors instead of swallowing them
pub fn toBoolWithError(value: anytype) !bool {
    const T = @TypeOf(value);
    const info = @typeInfo(T);

    // Handle integers
    if (info == .int or info == .comptime_int) {
        return value != 0;
    }

    // Handle floats
    if (info == .float or info == .comptime_float) {
        return value != 0.0;
    }

    // Handle bool
    if (T == bool) {
        return value;
    }

    // Handle slices (including strings)
    if (info == .pointer and info.pointer.size == .slice) {
        return value.len > 0;
    }

    // Handle single-item pointers to arrays (string literals)
    if (info == .pointer and info.pointer.size == .one) {
        const child_info = @typeInfo(info.pointer.child);
        if (child_info == .array) {
            return child_info.array.len > 0;
        }
        // Handle pointers to structs with __bool__ method (Python objects)
        if (child_info == .@"struct") {
            const ChildT = info.pointer.child;
            if (@hasDecl(ChildT, "__bool__")) {
                // Check if __bool__ takes a mutable pointer (self-mutating method)
                const bool_fn_info = @typeInfo(@TypeOf(ChildT.__bool__));
                const first_param_type = bool_fn_info.@"fn".params[0].type.?;
                const first_param_info = @typeInfo(first_param_type);

                const result = blk: {
                    if (first_param_info == .pointer and !first_param_info.pointer.is_const) {
                        // __bool__ takes *@This() (mutable) - value is already a pointer
                        if (info.pointer.is_const) {
                            // Cast away const if needed
                            break :blk @constCast(value).__bool__();
                        } else {
                            break :blk value.__bool__();
                        }
                    } else {
                        // __bool__ takes *const @This() or value - call directly
                        break :blk value.__bool__();
                    }
                };
                const ResultT = @TypeOf(result);
                if (@typeInfo(ResultT) == .bool) {
                    return result;
                }
                // Handle error union wrapping bool - propagate error
                if (@typeInfo(ResultT) == .error_union) {
                    const unwrapped = try result; // Propagate error
                    const UnwrappedT = @TypeOf(unwrapped);
                    if (@typeInfo(UnwrappedT) == .bool) {
                        return unwrapped;
                    }
                    return error.TypeError;
                }
                return error.TypeError;
            }
            // Check for __len__ as fallback (containers with 0 length are falsy)
            if (@hasDecl(ChildT, "__len__")) {
                const len = try value.__len__();
                return len > 0;
            }
        }
    }

    // Handle PyString
    if (T == PyString) {
        return value.len() > 0;
    }

    // Handle PyInt
    if (T == PyInt) {
        return value.value != 0;
    }

    // Handle PyBool
    if (T == PyBool) {
        return value.value;
    }

    // Handle optional
    if (info == .optional) {
        return value != null;
    }

    // Handle structs with __bool__ method (Python protocol)
    if (info == .@"struct") {
        if (@hasDecl(T, "__bool__")) {
            // Check if __bool__ takes a mutable pointer (self-mutating method)
            const bool_fn_info = @typeInfo(@TypeOf(T.__bool__));
            const first_param_type = bool_fn_info.@"fn".params[0].type.?;
            const first_param_info = @typeInfo(first_param_type);

            const result = blk: {
                if (first_param_info == .pointer and !first_param_info.pointer.is_const) {
                    // __bool__ takes *@This() (mutable) - need to cast away const
                    var mutable = @constCast(&value);
                    break :blk mutable.__bool__();
                } else {
                    // __bool__ takes *const @This() or value - call directly
                    break :blk value.__bool__();
                }
            };
            const ResultT = @TypeOf(result);
            if (@typeInfo(ResultT) == .bool) {
                return result;
            }
            // Handle error union wrapping bool - propagate error
            if (@typeInfo(ResultT) == .error_union) {
                const unwrapped = try result; // Propagate error
                const UnwrappedT = @TypeOf(unwrapped);
                if (@typeInfo(UnwrappedT) == .bool) {
                    return unwrapped;
                }
                return error.TypeError;
            }
            return error.TypeError;
        }
        // Check for __len__ as fallback (containers with 0 length are falsy)
        if (@hasDecl(T, "__len__")) {
            const len = try value.__len__();
            return len > 0;
        }
        // Check for NativeList first (has .items which is ArrayList, not slice)
        if (T == NativeList) {
            return value.items.items.len > 0;
        }
        // Check for .items field (ArrayListUnmanaged, etc.) - empty list is falsy
        if (@hasField(T, "items")) {
            return value.items.len > 0;
        }
        // Check for .count() method (HashMap/ArrayHashMap) - empty dict is falsy
        if (@hasDecl(T, "count")) {
            return value.count() > 0;
        }
    }

    // Handle arrays (fixed-size arrays) - empty is falsy, non-empty is truthy
    if (info == .array) {
        return info.array.len > 0;
    }

    // Handle tuples (anonymous structs with numbered fields) - empty tuple is falsy
    if (info == .@"struct" and info.@"struct".is_tuple) {
        return info.@"struct".fields.len > 0;
    }

    // Default: truthy for everything else (non-empty types)
    return true;
}

/// Concrete bool conversion for PyValue - avoids anytype monomorphization
/// This is the preferred function for codegen to use with NativeList elements
/// Python truthiness semantics:
/// - false for: 0, 0.0, false, "", [], {}, None
/// - true for everything else
pub fn toBoolValue(value: PyValue) bool {
    return switch (value) {
        .int => |i| i != 0,
        .float => |f| f != 0.0 and !std.math.isNan(f),
        .bool => |b| b,
        .string => |s| s.len > 0,
        .none => false,
        .list => |l| l.len > 0,
        .tuple => |t| t.len > 0,
        .bytes => |b| b.data.len > 0,
        .bigint => |b| !b.isZero(),
        .complex => |c| c.real != 0.0 or c.imag != 0.0, // 0j is falsy
        .ptr => true, // Pointers are truthy
    };
}

/// Validate that __bool__ returns bool (Python 3 requirement)
/// Returns error.TypeError if value is not bool
pub fn validateBoolReturn(value: anytype) PythonError!bool {
    const T = @TypeOf(value);
    if (@typeInfo(T) == .bool) {
        return value;
    }
    // Python 3: __bool__ MUST return bool (True or False)
    return PythonError.TypeError;
}

/// Validate that __float__ returns float (Python 3 requirement)
/// Returns error.TypeError if value is not float
/// NOTE: In Python 3, returning a float subclass from __float__ is deprecated
/// but still allowed (with DeprecationWarning). We extract __base_value__ for these cases.
pub fn validateFloatReturn(value: anytype) PythonError!f64 {
    const T = @TypeOf(value);
    const type_info = @typeInfo(T);
    if (type_info == .float or type_info == .comptime_float) {
        return value;
    }
    // Handle PyValue union (when __float__ returns stored value)
    if (T == PyValue) {
        switch (value) {
            .float => |f| return f,
            else => return PythonError.TypeError,
        }
    }
    // Handle struct with __base_value__ (float subclass)
    if (type_info == .@"struct") {
        if (@hasField(T, "__base_value__")) {
            const base_val = value.__base_value__;
            const base_type = @typeInfo(@TypeOf(base_val));
            if (base_type == .float or base_type == .comptime_float) {
                return @as(f64, base_val);
            }
        }
    }
    // Handle pointer to struct with __base_value__ (when __float__ returns self)
    // Python 3 allows returning float subclass from __float__ (deprecated but working)
    if (type_info == .pointer) {
        const child_type = type_info.pointer.child;
        const child_info = @typeInfo(child_type);
        if (child_info == .@"struct") {
            if (@hasField(child_type, "__base_value__")) {
                const base_val = value.__base_value__;
                const base_type = @typeInfo(@TypeOf(base_val));
                if (base_type == .float or base_type == .comptime_float) {
                    return @as(f64, base_val);
                }
            }
        }
    }
    // Python 3: __float__ MUST return float (not int or other types)
    // "ClassName.__float__ returned non-float (type int)"
    return PythonError.TypeError;
}
