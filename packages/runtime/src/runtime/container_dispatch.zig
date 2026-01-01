/// Container dispatch helpers for reducing monomorphization explosion
/// These functions replace inline @TypeOf/@hasField checks with centralized dispatch
/// Each helper compiles ONCE per element type, not per call site
const std = @import("std");
const PyValue = @import("../Objects/object.zig").PyValue;
const equality = @import("equality.zig");

/// Check if a type is string-like ([]const u8, []u8, or pointer to u8 array)
/// Used to properly compare string literals (*const [N:0]u8) with slices ([]const u8)
fn isStringLike(comptime T: type) bool {
    if (T == []const u8 or T == []u8) return true;
    const info = @typeInfo(T);
    // Check for pointer to array of u8 (includes sentinel-terminated like *const [3:0]u8)
    if (info == .pointer) {
        if (info.pointer.size == .one) {
            const child_info = @typeInfo(info.pointer.child);
            if (child_info == .array and child_info.array.child == u8) return true;
        }
    }
    return false;
}

/// Convert string-like value to slice - handles both slices and pointer-to-array
fn toStringSlice(comptime T: type, val: T) []const u8 {
    const info = @typeInfo(T);
    if (info == .pointer and info.pointer.size == .one) {
        // Pointer to array (e.g., *const [3:0]u8) - convert to slice
        // Just slice the whole array - this works for both sentinel and non-sentinel
        return val[0..];
    }
    // Already a slice
    return val;
}

/// Compare two containers for equality - handles arrays, slices, and structs with .items
/// This is the unified comparison function for assertEqual on sequences
/// Takes pointers to avoid by-value copying of arrays
pub fn slicesEqual(comptime T: type, comptime U: type, a: *const T, b: *const U) bool {
    const slice_a = getConstSliceFromPtr(T, a);
    const slice_b = getConstSliceFromPtr(U, b);
    // Get element type for std.mem.eql
    const ElemA = std.meta.Elem(@TypeOf(slice_a));
    const ElemB = std.meta.Elem(@TypeOf(slice_b));
    if (ElemA != ElemB) return false;
    return std.mem.eql(ElemA, slice_a, slice_b);
}

/// Get const slice from pointer to container - always returns []const T
/// Unlike getSlice which returns arrays by value, this takes a pointer and returns a slice
fn getConstSliceFromPtr(comptime T: type, ptr: *const T) []const GetElementType(T) {
    const info = @typeInfo(T);
    if (info == .@"struct" and @hasField(T, "list")) {
        return ptr.list.items;
    } else if (info == .@"struct" and @hasField(T, "items")) {
        return ptr.items;
    } else if (info == .@"struct" and @hasField(T, "data")) {
        return ptr.data;
    } else if (info == .pointer and info.pointer.size == .slice) {
        return ptr.*;
    } else if (info == .array) {
        // Array: return slice from pointer
        return ptr;
    }
    // Fallback for unknown types (like HashMaps)
    // Return empty slice of the expected element type
    return &[0]GetElementType(T){};
}

/// Extract slice from any container type
/// Handles: ArrayList (has .items), PyBytes (has .data), PyValue.list (has .list.items), fixed arrays, slices, tuples
/// Returns const slice for read operations
pub fn getSlice(comptime T: type, container: T) GetSliceType(T) {
    const info = @typeInfo(T);
    if (info == .@"struct" and @hasField(T, "list")) {
        // PyValue.list types - .list is *ArrayListUnmanaged, access .items
        return container.list.items;
    } else if (info == .@"struct" and @hasField(T, "items")) {
        return container.items;
    } else if (info == .@"struct" and @hasField(T, "data")) {
        // PyBytes-like types use .data field
        return container.data;
    } else if (info == .pointer and info.pointer.size == .slice) {
        return container;
    } else if (info == .array) {
        // Return array by value (not pointer) - avoids dangling pointer issue
        // when container is passed by value (parameter copy becomes invalid after return)
        return container;
    } else if (info == .@"struct" and info.@"struct".is_tuple) {
        // Tuple struct - return as-is (caller should use inline for with getAt)
        // Note: tuples can't be converted to slices directly, but getAt handles indexed access
        return container;
    }
    // Fallback for unknown types - return empty void slice
    // Must match GetSliceType(T) which returns []const void for unknown types
    return &[0]void{};
}

/// Get mutable slice from container pointer
/// For slice assignment operations
pub fn getMutSlice(comptime T: type, container: *T) GetMutSliceType(T) {
    const info = @typeInfo(T);
    if (info == .@"struct" and @hasField(T, "items")) {
        return container.items;
    } else if (info == .array) {
        return container;
    }
    // For pointer to slice, dereference
    if (info == .pointer and info.pointer.size == .one) {
        const child_info = @typeInfo(info.pointer.child);
        if (child_info == .pointer and child_info.pointer.size == .slice) {
            return container.*;
        }
    }
    // Fallback for unknown types - return empty void slice
    // Must match GetMutSliceType(T) which returns []void for unknown types
    return @constCast(&[0]void{});
}

/// Get container length
pub fn getLen(comptime T: type, container: T) usize {
    const info = @typeInfo(T);
    // Order matters: check comptime-known lengths first (no container access needed)
    if (info == .array) {
        return info.array.len;
    } else if (info == .@"struct" and info.@"struct".is_tuple) {
        // Tuple struct - length is number of fields (comptime-known)
        return info.@"struct".fields.len;
    } else if (info == .@"struct" and @hasField(T, "list")) {
        // PyValue.list types - .list is *ArrayListUnmanaged
        return container.list.items.len;
    } else if (info == .@"struct" and @hasField(T, "items")) {
        return container.items.len;
    } else if (info == .pointer and info.pointer.size == .slice) {
        return container.len;
    }
    return 0;
}

/// Get element at index from any container
pub fn getAt(comptime T: type, container: T, index: usize) GetElementType(T) {
    const info = @typeInfo(T);
    // For tuple structs, we need special handling since tuples can't be indexed by runtime usize
    // The index MUST be comptime-known for tuples
    if (info == .@"struct" and info.@"struct".is_tuple) {
        // Use inline switch to convert runtime index to comptime field access
        const fields = info.@"struct".fields;
        inline for (0..fields.len) |i| {
            if (index == i) {
                return @field(container, fields[i].name);
            }
        }
        // Index out of bounds
        unreachable;
    }
    // For other containers, use slice indexing
    const slice = getSlice(T, container);
    return slice[index];
}

/// Create iterator slice from any container - single dispatch point
/// Used by for loops and iter() builtin
pub fn toIterSlice(comptime T: type, container: T) GetSliceType(T) {
    return getSlice(T, container);
}

/// Helper to determine element type of a container
pub fn GetElementType(comptime T: type) type {
    const info = @typeInfo(T);
    if (info == .@"struct" and @hasField(T, "list")) {
        // PyValue.list types - .list is *ArrayListUnmanaged
        return std.meta.Elem(@TypeOf(@as(T, undefined).list.items));
    } else if (info == .@"struct" and @hasField(T, "items")) {
        return std.meta.Elem(@TypeOf(@as(T, undefined).items));
    } else if (info == .@"struct" and @hasField(T, "data")) {
        // PyBytes-like types use .data field
        return std.meta.Elem(@TypeOf(@as(T, undefined).data));
    } else if (info == .pointer and info.pointer.size == .slice) {
        return info.pointer.child;
    } else if (info == .array) {
        return info.array.child;
    } else if (info == .@"struct" and info.@"struct".is_tuple) {
        // Tuple struct (e.g., struct { f64, f64, f64 }) - elements accessed by field index
        // All tuple elements must have same type for iteration, use first field's type
        const fields = info.@"struct".fields;
        if (fields.len > 0) {
            return fields[0].type;
        }
    } else if (info == .@"struct" and @hasDecl(T, "KV")) {
        // Hash map types (std.AutoHashMap, std.AutoArrayHashMap) - use key type for containment
        // These have a KV type that tells us the key/value types
        return @TypeOf(@as(T.KV, undefined).key);
    }
    return void;
}

/// Helper to determine slice type for getSlice return
fn GetSliceType(comptime T: type) type {
    const info = @typeInfo(T);
    if (info == .@"struct" and @hasField(T, "list")) {
        // PyValue.list types - .list is *ArrayListUnmanaged
        return @TypeOf(@as(T, undefined).list.items);
    } else if (info == .@"struct" and @hasField(T, "items")) {
        return @TypeOf(@as(T, undefined).items);
    } else if (info == .@"struct" and @hasField(T, "data")) {
        // PyBytes-like types use .data field
        return @TypeOf(@as(T, undefined).data);
    } else if (info == .pointer and info.pointer.size == .slice) {
        return T;
    } else if (info == .array) {
        // Return array type as-is (not slice) - allows iteration by value
        // This avoids dangling pointer issue when array is passed by value to getSlice
        return T;
    } else if (info == .@"struct" and info.@"struct".is_tuple) {
        // Tuple struct - return the tuple type itself (used with inline for iteration)
        return T;
    }
    return []const void;
}

/// Helper to determine mutable slice type
fn GetMutSliceType(comptime T: type) type {
    const info = @typeInfo(T);
    if (info == .@"struct" and @hasField(T, "items")) {
        // ArrayList items is already mutable slice
        return @TypeOf(@as(T, undefined).items);
    } else if (info == .array) {
        return []info.array.child;
    }
    return []void;
}

/// Check if a type is an error union - used by assertRaises
/// Single comptime dispatch point replaces inline @typeInfo checks
pub fn isErrorUnion(comptime T: type) bool {
    return @typeInfo(T) == .error_union;
}

/// Check if a type is an error set - used by assertRaises
/// Single comptime dispatch point replaces inline @typeInfo checks
pub fn isErrorSet(comptime T: type) bool {
    return @typeInfo(T) == .error_set;
}

/// Set element at index in any container - for slice assignment
/// Handles: ArrayList (.items), arrays, slices
pub fn setAt(comptime T: type, container: *T, index: usize, value: GetElementType(T)) void {
    const info = @typeInfo(T);
    if (info == .@"struct" and @hasField(T, "items")) {
        container.items[index] = value;
    } else if (info == .array) {
        container[index] = value;
    } else if (info == .pointer and info.pointer.size == .one) {
        // Pointer to array or slice
        container.*[index] = value;
    } else {
        // Slice or other
        container[index] = value;
    }
}

/// Get length of deref'd container pointer - for slice assignment target
/// Handles: *ArrayList, *array, *slice
pub fn getPtrLen(comptime T: type, container: T) usize {
    const info = @typeInfo(T);
    if (info == .pointer and info.pointer.size == .one) {
        const child = info.pointer.child;
        const child_info = @typeInfo(child);
        if (child_info == .@"struct" and @hasField(child, "items")) {
            return container.items.len;
        } else if (child_info == .array) {
            return child_info.array.len;
        } else if (child_info == .pointer and child_info.pointer.size == .slice) {
            return container.*.len;
        }
    }
    return 0;
}

/// Set element at index in dereferenced container pointer - for slice assignment target
/// Handles: *ArrayList, *array, *slice
pub fn setPtrAt(comptime T: type, comptime E: type, container: T, index: usize, value: E) void {
    const info = @typeInfo(T);
    if (info == .pointer and info.pointer.size == .one) {
        const child = info.pointer.child;
        const child_info = @typeInfo(child);
        if (child_info == .@"struct" and @hasField(child, "items")) {
            container.items[index] = value;
        } else if (child_info == .array) {
            container[index] = value;
        } else {
            container.*[index] = value;
        }
    }
}

/// Check if value is contained in array/slice/tuple/hashmap - for 'in' operator
/// Handles: arrays, slices, ArrayList (.items), tuples, hash maps (sets/dicts)
/// Compiles ONCE per type, not per 'in' expression
/// Note: For type V where V != GetElementType(T), will attempt bitcast for float->u64 (Python set semantics)
pub fn contains(comptime T: type, container: T, value: anytype) bool {
    const info = @typeInfo(T);
    const V = @TypeOf(value);
    const K = GetElementType(T);

    // Special handling for tuples - inline iterate over fields
    if (info == .@"struct" and info.@"struct".is_tuple) {
        inline for (info.@"struct".fields) |field| {
            const field_val = @field(container, field.name);
            const FieldT = @TypeOf(field_val);
            // Check if both are string-like types (handles []const u8 vs *const [N:0]u8)
            const field_is_str = comptime isStringLike(FieldT);
            const value_is_str = comptime isStringLike(V);
            if (field_is_str and value_is_str) {
                // Convert both to slices for comparison
                const field_slice = toStringSlice(FieldT, field_val);
                const value_slice = toStringSlice(V, value);
                if (std.mem.eql(u8, field_slice, value_slice)) return true;
            } else if (FieldT == V) {
                // Same-type comparison with NaN handling for floats
                if (@typeInfo(V) == .float) {
                    // NaN identity: both being NaN counts as a match
                    if (std.math.isNan(value) and std.math.isNan(field_val)) return true;
                }
                if (field_val == value) return true;
            }
            // Cross-type: no match
        }
        return false;
    }
    // Special handling for hash maps (sets/dicts) - check key containment
    if (info == .@"struct" and @hasDecl(T, "contains")) {
        // Handle type mismatch: f64 value in u64 keyed map (Python float sets use bitcast)
        if (V == f64 and K == u64) {
            return container.contains(@bitCast(value));
        }
        // Handle type mismatch: f64/i64/etc value in PyValue container (wrap in PyValue)
        if (K == PyValue and V != PyValue) {
            return container.contains(PyValue.from(value));
        }
        // Use the map's built-in contains method
        return container.contains(value);
    }
    // Normal path for arrays/slices
    // Use pyContains instead of std.mem.indexOfScalar to handle NaN identity
    const slice = getSlice(T, container);
    return equality.pyContains(K, slice, value);
}

/// Check if value is NOT contained in array/slice - for 'not in' operator
pub fn notContains(comptime T: type, container: T, value: anytype) bool {
    return !contains(T, container, value);
}

/// String containment check - for 'in' operator
/// Handles two cases:
/// 1. String substring: 'abc' in 'abcdef' -> True (substring search)
/// 2. String in list: 'name' in dir(obj) -> True (list membership)
/// Handles both optional and non-optional inputs
pub fn stringContains(haystack: anytype, needle: anytype) bool {
    const H = @TypeOf(haystack);
    const h_info = @typeInfo(H);

    // Unwrap needle (the search target)
    const n: []const u8 = if (@typeInfo(@TypeOf(needle)) == .optional)
        needle orelse return false
    else
        needle;

    // Check if haystack is a list of strings (e.g., from dir())
    if (h_info == .pointer and h_info.pointer.size == .slice) {
        const child_info = @typeInfo(h_info.pointer.child);
        // If it's []const []const u8 (list of strings), use list containment
        if (child_info == .pointer and child_info.pointer.size == .slice) {
            return stringListContains(haystack, n);
        }
    }

    // Otherwise, treat haystack as a single string for substring search
    const h: []const u8 = if (h_info == .optional)
        haystack orelse return false
    else
        haystack;
    return std.mem.indexOf(u8, h, n) != null;
}

/// String NOT containment check - for 'not in' operator
/// Handles two cases:
/// 1. String substring: 'xyz' not in 'abcdef' -> True
/// 2. String in list: 'name' not in dir(obj) -> True
/// Handles both optional and non-optional inputs
pub fn stringNotContains(haystack: anytype, needle: anytype) bool {
    return !stringContains(haystack, needle);
}

/// Check if a string exists in a list of strings
/// Used for: "name" in dir(obj) where dir() returns []const []const u8
pub fn stringListContains(list: anytype, needle: []const u8) bool {
    const T = @TypeOf(list);
    const info = @typeInfo(T);

    // Handle slice of strings
    if (info == .pointer and info.pointer.size == .slice) {
        const child_info = @typeInfo(info.pointer.child);
        // Check if it's []const []const u8 or similar
        if (child_info == .pointer and child_info.pointer.size == .slice) {
            for (list) |item| {
                if (std.mem.eql(u8, item, needle)) return true;
            }
            return false;
        }
    }

    // Fallback: try iterating directly
    for (list) |item| {
        if (std.mem.eql(u8, item, needle)) return true;
    }
    return false;
}

/// Check if type is a slice - for identity comparison
/// Compiles ONCE per type, not per 'is'/'is not' expression
pub fn isSlice(comptime T: type) bool {
    const info = @typeInfo(T);
    return info == .pointer and info.pointer.size == .slice;
}

/// Check if type has a declaration (dunder method)
/// Handles both pointer types (*Rat) and value types (Rat)
/// Used for reverse dunder dispatch (__radd__, __rsub__, etc.)
/// Compiles ONCE per type, not per arithmetic expression
pub fn hasPtrChildDecl(comptime T: type, comptime decl_name: []const u8) bool {
    const info = @typeInfo(T);
    if (info == .pointer and info.pointer.size == .one) {
        return @hasDecl(info.pointer.child, decl_name);
    }
    // Also check struct types directly (for value types like `r: Rat`)
    if (info == .@"struct") {
        return @hasDecl(T, decl_name);
    }
    return false;
}

/// Get pointer child type if T is a single-item pointer, else void
pub fn getPtrChild(comptime T: type) type {
    const info = @typeInfo(T);
    if (info == .pointer and info.pointer.size == .one) {
        return info.pointer.child;
    }
    return void;
}

/// Check if key is in a dict (HashMap) - handles type mismatches safely
/// For `key in dict` where dict may have different key type than the key being checked
/// Returns false if key types are incompatible (like int key in StringHashMap)
/// Compiles ONCE per (dict_type, key_type) pair
pub fn dictContains(comptime DictType: type, comptime KeyType: type, dict: DictType, key: KeyType) bool {
    const dict_info = @typeInfo(DictType);

    // Extract the actual key type from the HashMap
    if (dict_info == .@"struct") {
        // Check if it has a .contains method
        if (@hasDecl(DictType, "contains")) {
            // Get the expected key type from the contains method signature
            const contains_fn = @typeInfo(@TypeOf(DictType.contains));
            if (contains_fn == .@"fn") {
                const params = contains_fn.@"fn".params;
                if (params.len >= 2) {
                    const expected_key = params[1].type orelse return false;
                    // If key types match exactly, do the contains check
                    if (expected_key == KeyType) {
                        return dict.contains(key);
                    }
                    // Handle comptime_int -> integer coercion
                    if (KeyType == comptime_int) {
                        const key_info = @typeInfo(expected_key);
                        if (key_info == .int) {
                            // Coerce comptime_int to the dict's key type
                            return dict.contains(@as(expected_key, key));
                        }
                    }
                    // Handle integer type coercion (e.g., i64 to usize)
                    const key_type_info = @typeInfo(KeyType);
                    const expected_info = @typeInfo(expected_key);
                    if (key_type_info == .int and expected_info == .int) {
                        // Both are integers - use std.math.cast for safe conversion
                        const converted = std.math.cast(expected_key, key);
                        if (converted) |conv_key| {
                            return dict.contains(conv_key);
                        }
                        // Key value out of range for dict's key type
                        return false;
                    }
                    // Type mismatch - key cannot be in dict
                    return false;
                }
            }
        }
    }

    // Fallback: type not recognized as dict, return false
    return false;
}

/// Extract path string from any value type for filesystem operations
/// Handles: []const u8 (passthrough), PyValue (.string field), *PyObject (eval result)
/// Returns empty string if value cannot be converted to a path
/// Used by os.remove, os.unlink, etc. where the path may come from eval()
pub fn toPathStr(comptime T: type, value: T) []const u8 {
    const info = @typeInfo(T);

    // Direct string slice - just return it
    if (info == .pointer and info.pointer.size == .slice and info.pointer.child == u8) {
        return value;
    }

    // Pointer to array of u8 (string literal: *const [N:0]u8 or *const [N]u8)
    if (info == .pointer and info.pointer.size == .one) {
        const child_info = @typeInfo(info.pointer.child);
        if (child_info == .array and child_info.array.child == u8) {
            // Coerce to slice
            return value[0..];
        }
    }

    // Array of u8 (embedded string: [N]u8)
    if (info == .array and info.array.child == u8) {
        return &value;
    }

    // PyValue - extract string field
    if (info == .@"union" and @hasField(T, "string")) {
        if (value == .string) {
            return value.string;
        }
        return "";
    }

    // Check for struct with asString method
    if (info == .@"struct" or info == .@"union") {
        if (@hasDecl(T, "asString")) {
            return value.asString();
        }
    }

    // Unknown type - return empty string
    return "";
}
