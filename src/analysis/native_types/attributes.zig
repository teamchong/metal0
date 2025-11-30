const std = @import("std");
const hashmap_helper = @import("hashmap_helper");
const ast = @import("ast");
const core = @import("core.zig");
const NativeType = core.NativeType;

/// Check if a list contains only literal values (candidates for array optimization)
pub fn isConstantList(list: ast.Node.List) bool {
    if (list.elts.len == 0) return false; // Empty lists stay dynamic

    for (list.elts) |elem| {
        // Check if element is a literal constant
        const is_literal = switch (elem) {
            .constant => true,
            else => false,
        };
        if (!is_literal) return false;
    }

    return true;
}

/// Check if all elements in a list have the same type (homogeneous)
pub fn allSameType(elements: []ast.Node) bool {
    if (elements.len == 0) return true;

    // Get type tag of first element
    const first_const = switch (elements[0]) {
        .constant => |c| c,
        else => return false,
    };

    const first_type_tag = @as(std.meta.Tag(@TypeOf(first_const.value)), first_const.value);

    // Check all other elements match
    for (elements[1..]) |elem| {
        const elem_const = switch (elem) {
            .constant => |c| c,
            else => return false,
        };

        const elem_type_tag = @as(std.meta.Tag(@TypeOf(elem_const.value)), elem_const.value);
        if (elem_type_tag != first_type_tag) return false;
    }

    return true;
}

/// Class field and method information
const FnvTypeMap = hashmap_helper.StringHashMap(NativeType);

pub const ClassInfo = struct {
    fields: FnvTypeMap,
    methods: FnvTypeMap, // method_name -> return type
    property_methods: FnvTypeMap, // methods decorated with @property
    allow_dynamic_attrs: bool = true, // Enable __dict__ for dynamic attributes
};

/// Comptime analysis: Does this type need allocator for operations?
/// Leverages Zig's comptime for zero-runtime-cost type analysis
/// - Analyzed at compile time, no runtime overhead
/// - Recursively checks composite types
/// - Used to determine if functions need allocator parameter
pub fn needsAllocator(self: NativeType) bool {
    return switch (self) {
        .string => true, // String operations allocate
        .bigint => true, // BigInt operations allocate
        .list, .dict => true, // Collection operations allocate
        .array => |arr| arr.element_type.needsAllocator(), // Recursive
        .tuple => |types| blk: {
            for (types) |t| {
                if (t.needsAllocator()) break :blk true;
            }
            break :blk false;
        },
        .function => |f| f.return_type.needsAllocator(), // Check return type
        else => false,
    };
}

/// Comptime check: Is return type error union?
pub fn isErrorUnion(self: NativeType) bool {
    return switch (self) {
        .string, .bigint, .list, .dict, .array => true, // These can fail allocation
        .function => |f| f.return_type.isErrorUnion(),
        else => false,
    };
}

/// Comptime function signature builder
/// Generates optimal function signature based on type analysis
pub const FunctionSignature = struct {
    params: []const NativeType,
    return_type: NativeType,
    needs_allocator: bool,
    is_error_union: bool,

    /// Comptime analysis of function requirements
    pub fn analyze(params: []const NativeType, ret: NativeType) FunctionSignature {
        // Check if any parameter or return needs allocator
        var needs_alloc = needsAllocator(ret);
        for (params) |p| {
            if (needsAllocator(p)) {
                needs_alloc = true;
                break;
            }
        }

        return .{
            .params = params,
            .return_type = ret,
            .needs_allocator = needs_alloc,
            .is_error_union = isErrorUnion(ret),
        };
    }

    /// Generate Zig function signature string (comptime-optimized)
    pub fn toZigSignature(self: FunctionSignature, func_name: []const u8, allocator: std.mem.Allocator) ![]const u8 {
        var buf = std.ArrayList(u8){};
        defer buf.deinit(allocator);

        try buf.appendSlice(allocator, "pub fn ");
        try buf.appendSlice(allocator, func_name);
        try buf.appendSlice(allocator, "(");

        // Add allocator parameter if needed (comptime-determined)
        if (self.needs_allocator) {
            try buf.appendSlice(allocator, "allocator: std.mem.Allocator");
            if (self.params.len > 0) {
                try buf.appendSlice(allocator, ", ");
            }
        }

        // Add parameters
        for (self.params, 0..) |param, i| {
            const param_name = try std.fmt.allocPrint(allocator, "arg{d}: ", .{i});
            defer allocator.free(param_name);
            try buf.appendSlice(allocator, param_name);

            var type_buf = std.ArrayList(u8){};
            defer type_buf.deinit(allocator);
            try param.toZigType(allocator, &type_buf);
            try buf.appendSlice(allocator, type_buf.items);

            if (i < self.params.len - 1) {
                try buf.appendSlice(allocator, ", ");
            }
        }

        try buf.appendSlice(allocator, ") ");

        // Add error union if needed (comptime-determined)
        if (self.is_error_union) {
            try buf.appendSlice(allocator, "!");
        }

        // Add return type
        var ret_buf = std.ArrayList(u8){};
        defer ret_buf.deinit(allocator);
        try self.return_type.toZigType(allocator, &ret_buf);
        try buf.appendSlice(allocator, ret_buf.items);

        return buf.toOwnedSlice(allocator);
    }
};
