/// Call type inference - infer types from function/method calls
const std = @import("std");
const ast = @import("../../ast.zig");
const core = @import("core.zig");
const fnv_hash = @import("../../utils/fnv_hash.zig");

pub const NativeType = core.NativeType;
pub const InferError = core.InferError;
pub const ClassInfo = core.ClassInfo;

// Static string maps for DCE optimization
const BuiltinFuncMap = std.StaticStringMap(NativeType).initComptime(.{
    .{ "len", NativeType.int },
    .{ "str", NativeType{ .string = .runtime } },
    .{ "int", NativeType.int },
    .{ "float", NativeType.float },
    .{ "bool", NativeType.bool },
    .{ "round", NativeType.int },
    .{ "chr", NativeType{ .string = .runtime } },
    .{ "ord", NativeType.int },
    .{ "min", NativeType.int },
    .{ "max", NativeType.int },
    .{ "sum", NativeType.int },
});

const StringMethods = std.StaticStringMap(NativeType).initComptime(.{
    .{ "upper", NativeType{ .string = .runtime } },
    .{ "lower", NativeType{ .string = .runtime } },
    .{ "strip", NativeType{ .string = .runtime } },
    .{ "lstrip", NativeType{ .string = .runtime } },
    .{ "rstrip", NativeType{ .string = .runtime } },
    .{ "capitalize", NativeType{ .string = .runtime } },
    .{ "title", NativeType{ .string = .runtime } },
    .{ "swapcase", NativeType{ .string = .runtime } },
    .{ "replace", NativeType{ .string = .runtime } },
    .{ "join", NativeType{ .string = .runtime } },
    .{ "center", NativeType{ .string = .runtime } },
    .{ "ljust", NativeType{ .string = .runtime } },
    .{ "rjust", NativeType{ .string = .runtime } },
    .{ "zfill", NativeType{ .string = .runtime } },
});

const StringBoolMethods = std.StaticStringMap(void).initComptime(.{
    .{ "startswith", {} },
    .{ "endswith", {} },
    .{ "isdigit", {} },
    .{ "isalpha", {} },
    .{ "isalnum", {} },
    .{ "isspace", {} },
    .{ "islower", {} },
    .{ "isupper", {} },
    .{ "isascii", {} },
    .{ "istitle", {} },
    .{ "isprintable", {} },
});

const StringIntMethods = std.StaticStringMap(void).initComptime(.{
    .{ "find", {} },
    .{ "count", {} },
    .{ "index", {} },
    .{ "rfind", {} },
    .{ "rindex", {} },
});

const DfColumnMethods = std.StaticStringMap(void).initComptime(.{
    .{ "sum", {} },
    .{ "mean", {} },
    .{ "min", {} },
    .{ "max", {} },
    .{ "std", {} },
});

const FnvContext = fnv_hash.FnvHashContext([]const u8);
const FnvHashMap = std.HashMap([]const u8, NativeType, FnvContext, 80);
const FnvClassMap = std.HashMap([]const u8, ClassInfo, FnvContext, 80);

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

        // Check if this is a class constructor (class_name matches a registered class)
        if (class_fields.get(func_name)) |class_info| {
            _ = class_info;
            return .{ .class_instance = func_name };
        }

        // Check for registered function return types (lambdas, etc.)
        if (func_return_types.get(func_name)) |return_type| {
            return return_type;
        }

        // Special case: abs() returns same type as input
        if (std.mem.eql(u8, func_name, "abs") and call.args.len > 0) {
            return try expressions.inferExpr(allocator, var_types, class_fields, func_return_types, call.args[0]);
        }

        // Look up in static map for other builtins
        if (BuiltinFuncMap.get(func_name)) |return_type| {
            return return_type;
        }
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
            }
        }

        // Check for module function calls (module.function) - single level
        if (attr.value.* == .name) {
            const module_name = attr.value.name.id;
            const func_name = attr.attr;

            // json.loads() returns PyObject (dict)
            if (std.mem.eql(u8, module_name, "json") and std.mem.eql(u8, func_name, "loads")) {
                return .unknown;
            }

            // math module functions - most return float
            if (std.mem.eql(u8, module_name, "math")) {
                // Functions that return int
                if (std.mem.eql(u8, func_name, "factorial") or
                    std.mem.eql(u8, func_name, "gcd") or
                    std.mem.eql(u8, func_name, "lcm"))
                {
                    return .int;
                }
                // Functions that return bool
                if (std.mem.eql(u8, func_name, "isnan") or
                    std.mem.eql(u8, func_name, "isinf") or
                    std.mem.eql(u8, func_name, "isfinite"))
                {
                    return .bool;
                }
                // All other math functions return float
                return .float;
            }

            // pandas.DataFrame() or pd.DataFrame()
            if ((std.mem.eql(u8, module_name, "pandas") or std.mem.eql(u8, module_name, "pd")) and
                std.mem.eql(u8, func_name, "DataFrame"))
            {
                return .dataframe;
            }

            // Check if this is a class instance method call
            const var_type = var_types.get(module_name) orelse .unknown;
            if (var_type == .class_instance) {
                const class_name = var_type.class_instance;
                if (class_fields.get(class_name)) |class_info| {
                    if (class_info.methods.get(attr.attr)) |method_return_type| {
                        return method_return_type;
                    }
                }
            }
        }

        const obj_type = try expressions.inferExpr(allocator, var_types, class_fields, func_return_types, attr.value.*);

        // String methods
        if (obj_type == .string) {
            if (StringMethods.get(attr.attr)) |return_type| {
                return return_type;
            }
            if (StringBoolMethods.has(attr.attr)) return .bool;
            if (StringIntMethods.has(attr.attr)) return .int;

            // split() returns list of runtime strings
            if (std.mem.eql(u8, attr.attr, "split")) {
                const elem_ptr = try allocator.create(NativeType);
                elem_ptr.* = .{ .string = .runtime };
                return .{ .list = elem_ptr };
            }
        }

        // Dict methods
        if (obj_type == .dict) {
            const method = attr.attr;
            if (std.mem.eql(u8, method, "keys")) {
                const elem_ptr = try allocator.create(NativeType);
                elem_ptr.* = .{ .string = .runtime };
                return .{ .list = elem_ptr };
            } else if (std.mem.eql(u8, method, "values")) {
                const elem_ptr = try allocator.create(NativeType);
                elem_ptr.* = obj_type.dict.value.*;
                return .{ .list = elem_ptr };
            } else if (std.mem.eql(u8, method, "items")) {
                const tuple_types = try allocator.alloc(NativeType, 2);
                tuple_types[0] = .{ .string = .runtime };
                tuple_types[1] = obj_type.dict.value.*;
                const tuple_ptr = try allocator.create(NativeType);
                tuple_ptr.* = .{ .tuple = tuple_types };
                return .{ .list = tuple_ptr };
            }
        }

        // DataFrame Column methods
        if (obj_type == .dataframe or
            (attr.value.* == .subscript and
            try expressions.inferExpr(allocator, var_types, class_fields, func_return_types, attr.value.subscript.value.*) == .dataframe))
        {
            if (DfColumnMethods.has(attr.attr)) return .float;
            if (std.mem.eql(u8, attr.attr, "describe")) return .unknown;
        }
    }

    return .unknown;
}
