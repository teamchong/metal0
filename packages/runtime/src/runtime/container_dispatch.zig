/// Container dispatch helpers for reducing monomorphization explosion
/// These functions replace inline @TypeOf/@hasField checks with centralized dispatch
/// Each helper compiles ONCE per element type, not per call site
const std = @import("std");

/// Extract slice from any container type
/// Handles: ArrayList (has .items), fixed arrays, slices
/// Returns const slice for read operations
pub fn getSlice(comptime T: type, container: T) GetSliceType(T) {
    const info = @typeInfo(T);
    if (info == .@"struct" and @hasField(T, "items")) {
        return container.items;
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
    if (info == .@"struct" and @hasField(T, "items")) {
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
    if (info == .@"struct" and @hasField(T, "items")) {
        return std.meta.Elem(@TypeOf(@as(T, undefined).items));
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
    if (info == .@"struct" and @hasField(T, "items")) {
        return @TypeOf(@as(T, undefined).items);
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
