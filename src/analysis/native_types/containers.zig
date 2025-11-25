const std = @import("std");
const ast = @import("../../ast.zig");
const core = @import("core.zig");
const NativeType = core.NativeType;

/// Generic type base name to handler mapping for DCE optimization
const GenericTypeHandler = enum { list, dict, optional };
const generic_type_map = std.StaticStringMap(GenericTypeHandler).initComptime(.{
    .{ "list", .list },
    .{ "dict", .dict },
    .{ "Optional", .optional },
});

/// Simple type hint to NativeType mapping for DCE optimization
const SimpleTypeHint = enum { int, float, bool, str };
const simple_type_map = std.StaticStringMap(SimpleTypeHint).initComptime(.{
    .{ "int", .int },
    .{ "float", .float },
    .{ "bool", .bool },
    .{ "str", .str },
});

/// Error set for type inference
pub const InferError = error{
    OutOfMemory,
};

/// Parse type annotation from AST node (handles both simple and generic types)
/// Examples: int, list[str], dict[str, int]
pub fn parseTypeAnnotation(node: ast.Node, allocator: std.mem.Allocator) InferError!NativeType {
    switch (node) {
        .name => |name| {
            return pythonTypeHintToNative(name.id, allocator);
        },
        .subscript => |subscript| {
            // Handle generic types like list[int], dict[str, int], Optional[int]
            if (subscript.value.* != .name) return .unknown;
            const base_type = subscript.value.name.id;

            if (generic_type_map.get(base_type)) |handler| {
                switch (handler) {
                    .list => {
                        // list[T]
                        const elem_type = try parseSliceType(subscript.slice, allocator);
                        const elem_ptr = try allocator.create(NativeType);
                        elem_ptr.* = elem_type;
                        return .{ .list = elem_ptr };
                    },
                    .dict => {
                        // dict[K, V]
                        const types = try parseSliceTupleTypes(subscript.slice, allocator);
                        if (types.len == 2) {
                            const key_ptr = try allocator.create(NativeType);
                            const val_ptr = try allocator.create(NativeType);
                            key_ptr.* = types[0];
                            val_ptr.* = types[1];
                            return .{ .dict = .{ .key = key_ptr, .value = val_ptr } };
                        }
                    },
                    .optional => {
                        // Optional[T]
                        const inner_type = try parseSliceType(subscript.slice, allocator);
                        const inner_ptr = try allocator.create(NativeType);
                        inner_ptr.* = inner_type;
                        return .{ .optional = inner_ptr };
                    },
                }
            }
            return .unknown;
        },
        else => return .unknown,
    }
}

/// Parse single type from slice (for list[T])
fn parseSliceType(slice: ast.Node.Slice, allocator: std.mem.Allocator) InferError!NativeType {
    switch (slice) {
        .index => |index| {
            return parseTypeAnnotation(index.*, allocator);
        },
        else => return .unknown,
    }
}

/// Parse tuple of types from slice (for dict[K, V])
fn parseSliceTupleTypes(slice: ast.Node.Slice, allocator: std.mem.Allocator) InferError![]NativeType {
    switch (slice) {
        .index => |index| {
            // Check if index is a tuple
            if (index.* == .tuple) {
                const tuple = index.tuple;
                const types = try allocator.alloc(NativeType, tuple.elts.len);
                for (tuple.elts, 0..) |elem, i| {
                    types[i] = try parseTypeAnnotation(elem, allocator);
                }
                return types;
            }
        },
        else => {},
    }
    return &[_]NativeType{};
}

/// Convert Python type hint string to NativeType
/// Handles both simple types (int, str) and generic types from parser (tuple[str, str], list[int])
pub fn pythonTypeHintToNative(type_hint: ?[]const u8, allocator: std.mem.Allocator) InferError!NativeType {
    if (type_hint) |hint| {
        // Check for simple type first
        if (simple_type_map.get(hint)) |simple| {
            return switch (simple) {
                .int => .int,
                .float => .float,
                .bool => .bool,
                .str => .{ .string = .runtime },
            };
        }

        // Check for generic type (contains '[')
        if (std.mem.indexOf(u8, hint, "[")) |bracket_pos| {
            const base_type = hint[0..bracket_pos];
            const end_bracket = std.mem.lastIndexOf(u8, hint, "]") orelse return .unknown;
            const type_args_str = hint[bracket_pos + 1 .. end_bracket];

            // Handle tuple[T, U, ...]
            if (std.mem.eql(u8, base_type, "tuple")) {
                // Parse comma-separated type args
                var types = std.ArrayList(NativeType){};
                defer types.deinit(allocator);

                var iter = std.mem.splitSequence(u8, type_args_str, ", ");
                while (iter.next()) |arg| {
                    const trimmed = std.mem.trim(u8, arg, " ");
                    if (trimmed.len > 0) {
                        const elem_type = try pythonTypeHintToNative(trimmed, allocator);
                        try types.append(allocator, elem_type);
                    }
                }

                if (types.items.len > 0) {
                    const tuple_types = try allocator.dupe(NativeType, types.items);
                    return .{ .tuple = tuple_types };
                }
                return .unknown;
            }

            // Handle list[T]
            if (std.mem.eql(u8, base_type, "list")) {
                const elem_type = try pythonTypeHintToNative(type_args_str, allocator);
                const elem_ptr = try allocator.create(NativeType);
                elem_ptr.* = elem_type;
                return .{ .list = elem_ptr };
            }

            // Handle dict[K, V]
            if (std.mem.eql(u8, base_type, "dict")) {
                var iter = std.mem.splitSequence(u8, type_args_str, ", ");
                const key_str = iter.next() orelse return .unknown;
                const val_str = iter.next() orelse return .unknown;

                const key_type = try pythonTypeHintToNative(std.mem.trim(u8, key_str, " "), allocator);
                const val_type = try pythonTypeHintToNative(std.mem.trim(u8, val_str, " "), allocator);

                const key_ptr = try allocator.create(NativeType);
                const val_ptr = try allocator.create(NativeType);
                key_ptr.* = key_type;
                val_ptr.* = val_type;
                return .{ .dict = .{ .key = key_ptr, .value = val_ptr } };
            }

            // Handle Optional[T]
            if (std.mem.eql(u8, base_type, "Optional")) {
                const inner_type = try pythonTypeHintToNative(type_args_str, allocator);
                const inner_ptr = try allocator.create(NativeType);
                inner_ptr.* = inner_type;
                return .{ .optional = inner_ptr };
            }

            // Handle set[T]
            if (std.mem.eql(u8, base_type, "set")) {
                const elem_type = try pythonTypeHintToNative(type_args_str, allocator);
                const elem_ptr = try allocator.create(NativeType);
                elem_ptr.* = elem_type;
                return .{ .set = elem_ptr };
            }
        }

        // Generic list without type parameter
        if (std.mem.eql(u8, hint, "list")) return .unknown;
        if (std.mem.eql(u8, hint, "tuple")) return .unknown;
        if (std.mem.eql(u8, hint, "dict")) return .unknown;
        if (std.mem.eql(u8, hint, "set")) return .unknown;
    }
    return .unknown;
}
