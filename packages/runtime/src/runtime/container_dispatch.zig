/// Container dispatch helpers for reducing monomorphization explosion
/// These functions replace inline @TypeOf/@hasField checks with centralized dispatch
/// Each helper compiles ONCE per element type, not per call site
const std = @import("std");

/// Extract slice from any container type
/// Handles: ArrayList (has .items), PyBytes (has .data), PyValue.list (has .list.items), fixed arrays, slices
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
        return &container;
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
    if (info == .@"struct" and @hasField(T, "list")) {
        // PyValue.list types - .list is *ArrayListUnmanaged
        return container.list.items.len;
    } else if (info == .@"struct" and @hasField(T, "items")) {
        return container.items.len;
    } else if (info == .pointer and info.pointer.size == .slice) {
        return container.len;
    } else if (info == .array) {
        return info.array.len;
    }
    return 0;
}

/// Get element at index from any container
pub fn getAt(comptime T: type, container: T, index: usize) GetElementType(T) {
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
        return []const info.array.child;
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
