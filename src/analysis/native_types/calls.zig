/// Call type inference - infer types from function/method calls
/// This module coordinates type inference for all types of calls:
/// - Builtin functions: int(), str(), len(), abs(), etc.
/// - Module functions: json.dumps(), math.sqrt(), np.array(), etc.
/// - Instance methods: "hello".upper(), [1,2,3].append(), etc.
/// - User-defined functions and class constructors
const std = @import("std");
const ast = @import("ast");
const core = @import("core.zig");
const fnv_hash = @import("fnv_hash");

// Import submodules
const static_maps = @import("calls/static_maps.zig");
const builtin_calls = @import("calls/builtin_calls.zig");
const method_calls = @import("calls/method_calls.zig");
const module_calls = @import("calls/module_calls.zig");

pub const NativeType = core.NativeType;
pub const InferError = core.InferError;
pub const ClassInfo = core.ClassInfo;

const hashmap_helper = @import("hashmap_helper");
const FnvHashMap = hashmap_helper.StringHashMap(NativeType);
const FnvClassMap = hashmap_helper.StringHashMap(ClassInfo);

// Forward declaration for inferExpr (from expressions.zig)
const expressions = @import("expressions.zig");

/// Infer type from function/method call
pub fn inferCall(
    allocator: std.mem.Allocator,
    var_types: *FnvHashMap,
    class_fields: *FnvClassMap,
    func_return_types: *FnvHashMap,
    call: ast.Node.Call,
) InferError!NativeType {
    // Check if this is a registered function (lambda or regular function)
    if (call.func.* == .name) {
        const func_name = call.func.name.id;
        return try builtin_calls.inferBuiltinCall(
            allocator,
            var_types,
            class_fields,
            func_return_types,
            func_name,
            call,
        );
    }

    // Check if this is a method call (attribute access)
    if (call.func.* == .attribute) {
        const attr = call.func.attribute;

        // Helper to build full qualified name for nested attributes
        const buildQualifiedName = struct {
            fn build(node: *const ast.Node, buf: []u8) []const u8 {
                if (node.* == .name) {
                    const name = node.name.id;
                    if (name.len > buf.len) return &[_]u8{};
                    @memcpy(buf[0..name.len], name);
                    return buf[0..name.len];
                } else if (node.* == .attribute) {
                    const prefix = build(node.attribute.value, buf);
                    if (prefix.len == 0) return &[_]u8{};
                    const attr_name = node.attribute.attr;
                    const total_len = prefix.len + 1 + attr_name.len;
                    if (total_len > buf.len) return &[_]u8{};
                    buf[prefix.len] = '.';
                    @memcpy(buf[prefix.len + 1 .. total_len], attr_name);
                    return buf[0..total_len];
                }
                return &[_]u8{};
            }
        }.build;

        // Build full qualified name including the function
        var buf: [512]u8 = undefined;
        const prefix = buildQualifiedName(attr.value, buf[0..]);
        if (prefix.len > 0) {
            const total_len = prefix.len + 1 + attr.attr.len;
            if (total_len <= buf.len) {
                buf[prefix.len] = '.';
                @memcpy(buf[prefix.len + 1 .. total_len], attr.attr);
                const qualified_name = buf[0..total_len];

                if (func_return_types.get(qualified_name)) |return_type| {
                    return return_type;
                }

                // Check for os.path module
                if (std.mem.eql(u8, prefix, "os.path") or std.mem.eql(u8, prefix, "path")) {
                    const func_name_os = attr.attr;
                    if (std.mem.eql(u8, func_name_os, "exists") or
                        std.mem.eql(u8, func_name_os, "isfile") or
                        std.mem.eql(u8, func_name_os, "isdir"))
                    {
                        return .bool;
                    }
                    if (std.mem.eql(u8, func_name_os, "join") or
                        std.mem.eql(u8, func_name_os, "dirname") or
                        std.mem.eql(u8, func_name_os, "basename") or
                        std.mem.eql(u8, func_name_os, "abspath") or
                        std.mem.eql(u8, func_name_os, "realpath"))
                    {
                        return .{ .string = .runtime };
                    }
                    // os.path.split() and splitext() return tuple of (string, string)
                    if (std.mem.eql(u8, func_name_os, "split") or
                        std.mem.eql(u8, func_name_os, "splitext"))
                    {
                        const tuple_elems = try allocator.alloc(NativeType, 2);
                        tuple_elems[0] = .{ .string = .runtime };
                        tuple_elems[1] = .{ .string = .runtime };
                        return .{ .tuple = tuple_elems };
                    }
                }
            }
        }

        // Check for module function calls (module.function) - single level
        if (attr.value.* == .name) {
            const module_name = attr.value.name.id;
            const func_name = attr.attr;

            // First check if this is a class instance method call
            const var_type = var_types.get(module_name) orelse .unknown;
            if (var_type == .class_instance) {
                const class_name = var_type.class_instance;
                if (class_fields.get(class_name)) |class_info| {
                    if (class_info.methods.get(attr.attr)) |method_return_type| {
                        return method_return_type;
                    }
                }
            }

            // Otherwise, try module function call
            const result = try module_calls.inferModuleFunctionCall(
                allocator,
                var_types,
                class_fields,
                func_return_types,
                module_name,
                func_name,
            );
            if (@as(std.meta.Tag(NativeType), result) != .unknown) {
                return result;
            }
        }

        // Infer object type and check for instance methods
        const obj_type = try expressions.inferExpr(allocator, var_types, class_fields, func_return_types, attr.value.*);

        // Class instance method calls (handles chained access like self.foo.get_val())
        if (obj_type == .class_instance) {
            const class_name = obj_type.class_instance;
            if (class_fields.get(class_name)) |class_info| {
                if (class_info.methods.get(attr.attr)) |method_return_type| {
                    return method_return_type;
                }
            }
        }

        // Try instance method call
        return try method_calls.inferMethodCall(
            allocator,
            var_types,
            class_fields,
            func_return_types,
            obj_type,
            attr.attr,
            call,
        );
    }

    return .unknown;
}
