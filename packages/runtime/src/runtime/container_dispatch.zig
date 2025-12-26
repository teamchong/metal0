/// Container dispatch helpers for reducing monomorphization explosion
/// These functions replace inline @TypeOf/@hasField checks with centralized dispatch
/// Each helper compiles ONCE per element type, not per call site
const std = @import("std");

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
    // Fallback for unknown types - return empty slice
    return &[0]GetElementType(T){};
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
    return @constCast(&[0]GetElementType(T){});
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

/// Check if value is contained in array/slice - for 'in' operator
/// Handles: arrays, slices, ArrayList (.items)
/// Compiles ONCE per type, not per 'in' expression
pub fn contains(comptime T: type, container: T, value: GetElementType(T)) bool {
    const slice = getSlice(T, container);
    return std.mem.indexOfScalar(GetElementType(T), slice, value) != null;
}

/// Check if value is NOT contained in array/slice - for 'not in' operator
pub fn notContains(comptime T: type, container: T, value: GetElementType(T)) bool {
    return !contains(T, container, value);
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
                    // If key types match, do the contains check
                    if (expected_key == KeyType) {
                        return dict.contains(key);
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
