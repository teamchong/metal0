/// Call type inference - infer types from function/method calls
const std = @import("std");
const ast = @import("ast");
const core = @import("core.zig");
const fnv_hash = @import("fnv_hash");

pub const NativeType = core.NativeType;
pub const InferError = core.InferError;
pub const ClassInfo = core.ClassInfo;

// Static string maps for DCE optimization
const BuiltinFuncMap = std.StaticStringMap(NativeType).initComptime(.{
    .{ "len", NativeType.int },
    .{ "str", NativeType{ .string = .runtime } },
    .{ "repr", NativeType{ .string = .runtime } },
    .{ "int", NativeType.int },
    .{ "float", NativeType.float },
    .{ "bool", NativeType.bool },
    .{ "round", NativeType.int },
    .{ "chr", NativeType{ .string = .runtime } },
    .{ "ord", NativeType.int },
    .{ "min", NativeType.int },
    .{ "max", NativeType.int },
    .{ "sum", NativeType.int },
    .{ "hash", NativeType.int },
    // io module (from io import StringIO, BytesIO)
    .{ "StringIO", NativeType.stringio },
    .{ "BytesIO", NativeType.bytesio },
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

// Math module function return types
const MathIntFuncs = std.StaticStringMap(void).initComptime(.{
    .{ "factorial", {} },
    .{ "gcd", {} },
    .{ "lcm", {} },
});

const MathBoolFuncs = std.StaticStringMap(void).initComptime(.{
    .{ "isnan", {} },
    .{ "isinf", {} },
    .{ "isfinite", {} },
});

// NumPy functions that return numpy arrays
const NumpyArrayFuncs = std.StaticStringMap(void).initComptime(.{
    // Array creation
    .{ "array", {} },
    .{ "zeros", {} },
    .{ "ones", {} },
    .{ "empty", {} },
    .{ "full", {} },
    .{ "eye", {} },
    .{ "identity", {} },
    .{ "arange", {} },
    .{ "linspace", {} },
    .{ "logspace", {} },
    // Array manipulation
    .{ "reshape", {} },
    .{ "ravel", {} },
    .{ "flatten", {} },
    .{ "transpose", {} },
    .{ "squeeze", {} },
    .{ "expand_dims", {} },
    .{ "concatenate", {} },
    .{ "vstack", {} },
    .{ "hstack", {} },
    .{ "stack", {} },
    // Element-wise math
    .{ "add", {} },
    .{ "subtract", {} },
    .{ "multiply", {} },
    .{ "divide", {} },
    .{ "power", {} },
    .{ "sqrt", {} },
    .{ "exp", {} },
    .{ "log", {} },
    .{ "sin", {} },
    .{ "cos", {} },
    .{ "abs", {} },
    // Linear algebra that returns arrays
    .{ "matmul", {} },
    .{ "outer", {} },
    // Conditional and rounding
    .{ "where", {} },
    .{ "clip", {} },
    .{ "floor", {} },
    .{ "ceil", {} },
    .{ "round", {} },
    .{ "rint", {} },
    // Sorting (returns arrays)
    .{ "sort", {} },
    .{ "argsort", {} },
    .{ "unique", {} },
    // Copying
    .{ "copy", {} },
    .{ "asarray", {} },
    // Repeating/flipping
    .{ "tile", {} },
    .{ "repeat", {} },
    .{ "flip", {} },
    .{ "flipud", {} },
    .{ "fliplr", {} },
    // Cumulative
    .{ "cumsum", {} },
    .{ "cumprod", {} },
    .{ "diff", {} },
    // Matrix construction
    .{ "diag", {} },
    .{ "triu", {} },
    .{ "tril", {} },
    // Additional math
    .{ "tan", {} },
    .{ "arcsin", {} },
    .{ "arccos", {} },
    .{ "arctan", {} },
    .{ "sinh", {} },
    .{ "cosh", {} },
    .{ "tanh", {} },
    .{ "log10", {} },
    .{ "log2", {} },
    .{ "exp2", {} },
    .{ "expm1", {} },
    .{ "log1p", {} },
    .{ "sign", {} },
    .{ "negative", {} },
    .{ "reciprocal", {} },
    .{ "square", {} },
    .{ "cbrt", {} },
    .{ "maximum", {} },
    .{ "minimum", {} },
    .{ "mod", {} },
    .{ "remainder", {} },
    // Array manipulation (roll, rot90, pad, take, put, cross)
    .{ "roll", {} },
    .{ "rot90", {} },
    .{ "pad", {} },
    .{ "take", {} },
    .{ "put", {} },
    .{ "cross", {} },
    // Logical array operations
    .{ "logical_and", {} },
    .{ "logical_or", {} },
    .{ "logical_not", {} },
    .{ "logical_xor", {} },
    .{ "isin", {} },
    .{ "isnan", {} },
    .{ "isinf", {} },
    .{ "isfinite", {} },
    // Set functions
    .{ "setdiff1d", {} },
    .{ "union1d", {} },
    .{ "intersect1d", {} },
    // Numerical functions
    .{ "gradient", {} },
    .{ "interp", {} },
    .{ "convolve", {} },
    .{ "correlate", {} },
    // Utility functions
    .{ "nonzero", {} },
    .{ "flatnonzero", {} },
    .{ "meshgrid", {} },
    .{ "histogram", {} },
    .{ "bincount", {} },
    .{ "digitize", {} },
    .{ "nan_to_num", {} },
    .{ "absolute", {} },
    .{ "fabs", {} },
    // Advanced linalg
    .{ "qr", {} },
    .{ "cholesky", {} },
    .{ "eig", {} },
    .{ "svd", {} },
    .{ "lstsq", {} },
});

// NumPy functions that return scalars (float)
const NumpyScalarFuncs = std.StaticStringMap(void).initComptime(.{
    .{ "sum", {} },
    .{ "mean", {} },
    .{ "std", {} },
    .{ "var", {} },
    .{ "min", {} },
    .{ "max", {} },
    .{ "prod", {} },
    .{ "dot", {} },
    .{ "inner", {} },
    .{ "vdot", {} },
    .{ "trace", {} },
    .{ "median", {} },
    .{ "percentile", {} },
    .{ "norm", {} },
    .{ "det", {} },
    .{ "trapz", {} },
});

// NumPy functions that return integers
const NumpyIntFuncs = std.StaticStringMap(void).initComptime(.{
    .{ "argmin", {} },
    .{ "argmax", {} },
    .{ "searchsorted", {} },
    .{ "count_nonzero", {} },
});

// NumPy functions that return booleans
const NumpyBoolFuncs = std.StaticStringMap(void).initComptime(.{
    .{ "allclose", {} },
    .{ "array_equal", {} },
    .{ "any", {} },
    .{ "all", {} },
});

// NumPy random functions that return arrays
const NumpyRandomArrayFuncs = std.StaticStringMap(void).initComptime(.{
    .{ "rand", {} },
    .{ "randn", {} },
    .{ "randint", {} },
    .{ "uniform", {} },
    .{ "choice", {} },
    .{ "permutation", {} },
});

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
        const ABS_HASH = comptime fnv_hash.hash("abs");
        if (fnv_hash.hash(func_name) == ABS_HASH and call.args.len > 0) {
            return try expressions.inferExpr(allocator, var_types, class_fields, func_return_types, call.args[0]);
        }

        // Look up in static map for other builtins
        if (BuiltinFuncMap.get(func_name)) |return_type| {
            return return_type;
        }

        // Path() constructor from pathlib
        if (fnv_hash.hash(func_name) == comptime fnv_hash.hash("Path")) {
            return .path;
        }

        // Flask() constructor
        if (fnv_hash.hash(func_name) == comptime fnv_hash.hash("Flask")) {
            return .flask_app;
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

                // Check for nested numpy modules: np.random.*, np.linalg.*
                // prefix is "np.random" or "numpy.random", etc.
                if (std.mem.startsWith(u8, prefix, "np.random") or
                    std.mem.startsWith(u8, prefix, "numpy.random"))
                {
                    if (NumpyRandomArrayFuncs.has(attr.attr)) return .numpy_array;
                    // seed() and shuffle() return void (handled in codegen)
                }
                if (std.mem.startsWith(u8, prefix, "np.linalg") or
                    std.mem.startsWith(u8, prefix, "numpy.linalg"))
                {
                    // Most linalg functions return scalars (norm, det)
                    if (NumpyScalarFuncs.has(attr.attr)) return .float;
                    // inv, solve, eig, svd return arrays
                    return .numpy_array;
                }
            }
        }

        // Check for module function calls (module.function) - single level
        if (attr.value.* == .name) {
            const module_name = attr.value.name.id;
            const func_name = attr.attr;

            // Module function dispatch using hash for module name
            const module_hash = fnv_hash.hash(module_name);
            const JSON_HASH = comptime fnv_hash.hash("json");
            const MATH_HASH = comptime fnv_hash.hash("math");
            const PANDAS_HASH = comptime fnv_hash.hash("pandas");
            const PD_HASH = comptime fnv_hash.hash("pd");
            const NUMPY_HASH = comptime fnv_hash.hash("numpy");
            const NP_HASH = comptime fnv_hash.hash("np");
            const IO_HASH = comptime fnv_hash.hash("io");
            const HASHLIB_HASH = comptime fnv_hash.hash("hashlib");
            const STRUCT_HASH = comptime fnv_hash.hash("struct");
            const BASE64_HASH = comptime fnv_hash.hash("base64");
            const PICKLE_HASH = comptime fnv_hash.hash("pickle");
            const HMAC_HASH = comptime fnv_hash.hash("hmac");
            const SOCKET_HASH = comptime fnv_hash.hash("socket");

            switch (module_hash) {
                BASE64_HASH => {
                    // All base64 functions return bytes/string
                    return .{ .string = .runtime };
                },
                HMAC_HASH => {
                    // hmac.new() and hmac.digest() return bytes, compare_digest returns bool
                    const func_hash = fnv_hash.hash(func_name);
                    const COMPARE_DIGEST_HASH = comptime fnv_hash.hash("compare_digest");
                    if (func_hash == COMPARE_DIGEST_HASH) return .bool;
                    return .{ .string = .runtime }; // new/digest return hex strings
                },
                SOCKET_HASH => {
                    // socket module type inference
                    const func_hash = fnv_hash.hash(func_name);
                    // String-returning functions
                    const GETHOSTNAME_HASH = comptime fnv_hash.hash("gethostname");
                    const GETFQDN_HASH = comptime fnv_hash.hash("getfqdn");
                    const INET_NTOA_HASH = comptime fnv_hash.hash("inet_ntoa");
                    const INET_ATON_HASH = comptime fnv_hash.hash("inet_aton");
                    // Int-returning functions
                    const SOCKET_HASH_FN = comptime fnv_hash.hash("socket");
                    const CREATE_CONNECTION_HASH = comptime fnv_hash.hash("create_connection");
                    const HTONS_HASH = comptime fnv_hash.hash("htons");
                    const HTONL_HASH = comptime fnv_hash.hash("htonl");
                    const NTOHS_HASH = comptime fnv_hash.hash("ntohs");
                    const NTOHL_HASH = comptime fnv_hash.hash("ntohl");

                    if (func_hash == GETHOSTNAME_HASH or
                        func_hash == GETFQDN_HASH or
                        func_hash == INET_NTOA_HASH or
                        func_hash == INET_ATON_HASH)
                    {
                        return .{ .string = .runtime };
                    }
                    if (func_hash == SOCKET_HASH_FN or
                        func_hash == CREATE_CONNECTION_HASH or
                        func_hash == HTONS_HASH or
                        func_hash == HTONL_HASH or
                        func_hash == NTOHS_HASH or
                        func_hash == NTOHL_HASH)
                    {
                        return .int;
                    }
                    return .none; // setdefaulttimeout, etc.
                },
                PICKLE_HASH => {
                    // pickle.dumps() returns bytes, pickle.loads() returns dynamic value
                    const func_hash = fnv_hash.hash(func_name);
                    const DUMPS_HASH = comptime fnv_hash.hash("dumps");
                    const DUMP_HASH = comptime fnv_hash.hash("dump");
                    if (func_hash == DUMPS_HASH) return .{ .string = .runtime };
                    if (func_hash == DUMP_HASH) return .none; // writes to file
                    return .unknown; // loads/load return dynamic values
                },
                STRUCT_HASH => {
                    // struct.calcsize() returns int, struct.pack() returns bytes (string)
                    const func_hash = fnv_hash.hash(func_name);
                    const CALCSIZE_HASH = comptime fnv_hash.hash("calcsize");
                    const PACK_HASH = comptime fnv_hash.hash("pack");
                    const UNPACK_HASH = comptime fnv_hash.hash("unpack");
                    if (func_hash == CALCSIZE_HASH) return .int;
                    if (func_hash == PACK_HASH) return .{ .string = .runtime }; // bytes
                    if (func_hash == UNPACK_HASH) return .unknown; // tuple of values (dynamic)
                },
                HASHLIB_HASH => {
                    // hashlib.md5(), sha1(), sha256(), etc. all return HashObject
                    const func_hash = fnv_hash.hash(func_name);
                    const MD5_HASH = comptime fnv_hash.hash("md5");
                    const SHA1_HASH = comptime fnv_hash.hash("sha1");
                    const SHA224_HASH = comptime fnv_hash.hash("sha224");
                    const SHA256_HASH = comptime fnv_hash.hash("sha256");
                    const SHA384_HASH = comptime fnv_hash.hash("sha384");
                    const SHA512_HASH = comptime fnv_hash.hash("sha512");
                    const NEW_HASH = comptime fnv_hash.hash("new");
                    if (func_hash == MD5_HASH or
                        func_hash == SHA1_HASH or
                        func_hash == SHA224_HASH or
                        func_hash == SHA256_HASH or
                        func_hash == SHA384_HASH or
                        func_hash == SHA512_HASH or
                        func_hash == NEW_HASH)
                    {
                        return .hash_object;
                    }
                },
                IO_HASH => {
                    const func_hash = fnv_hash.hash(func_name);
                    if (func_hash == comptime fnv_hash.hash("StringIO")) return .stringio;
                    if (func_hash == comptime fnv_hash.hash("BytesIO")) return .bytesio;
                    if (func_hash == comptime fnv_hash.hash("open")) return .file;
                },
                JSON_HASH => if (fnv_hash.hash(func_name) == comptime fnv_hash.hash("loads")) return .unknown,
                MATH_HASH => {
                    if (MathIntFuncs.has(func_name)) return .int;
                    if (MathBoolFuncs.has(func_name)) return .bool;
                    return .float; // All other math functions return float
                },
                PANDAS_HASH, PD_HASH => if (fnv_hash.hash(func_name) == comptime fnv_hash.hash("DataFrame")) return .dataframe,
                NUMPY_HASH, NP_HASH => {
                    // NumPy function type inference
                    if (NumpyArrayFuncs.has(func_name)) return .numpy_array;
                    if (NumpyScalarFuncs.has(func_name)) return .float;
                    if (NumpyIntFuncs.has(func_name)) return .int;
                    if (NumpyBoolFuncs.has(func_name)) return .bool;
                },
                else => {},
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

        // Class instance method calls (handles chained access like self.foo.get_val())
        if (obj_type == .class_instance) {
            const class_name = obj_type.class_instance;
            if (class_fields.get(class_name)) |class_info| {
                if (class_info.methods.get(attr.attr)) |method_return_type| {
                    return method_return_type;
                }
            }
        }

        // String methods
        if (obj_type == .string) {
            if (StringMethods.get(attr.attr)) |return_type| {
                return return_type;
            }
            if (StringBoolMethods.has(attr.attr)) return .bool;
            if (StringIntMethods.has(attr.attr)) return .int;

            // split() returns list of runtime strings
            if (fnv_hash.hash(attr.attr) == comptime fnv_hash.hash("split")) {
                const elem_ptr = try allocator.create(NativeType);
                elem_ptr.* = .{ .string = .runtime };
                return .{ .list = elem_ptr };
            }
        }

        // Dict methods using hash-based dispatch
        if (obj_type == .dict) {
            const method_hash = fnv_hash.hash(attr.attr);
            const KEYS_HASH = comptime fnv_hash.hash("keys");
            const VALUES_HASH = comptime fnv_hash.hash("values");
            const ITEMS_HASH = comptime fnv_hash.hash("items");

            switch (method_hash) {
                KEYS_HASH => {
                    const elem_ptr = try allocator.create(NativeType);
                    elem_ptr.* = .{ .string = .runtime };
                    return .{ .list = elem_ptr };
                },
                VALUES_HASH => {
                    const elem_ptr = try allocator.create(NativeType);
                    elem_ptr.* = obj_type.dict.value.*;
                    return .{ .list = elem_ptr };
                },
                ITEMS_HASH => {
                    const tuple_types = try allocator.alloc(NativeType, 2);
                    tuple_types[0] = .{ .string = .runtime };
                    tuple_types[1] = obj_type.dict.value.*;
                    const tuple_ptr = try allocator.create(NativeType);
                    tuple_ptr.* = .{ .tuple = tuple_types };
                    return .{ .list = tuple_ptr };
                },
                else => {},
            }
        }

        // DataFrame Column methods
        if (obj_type == .dataframe or
            (attr.value.* == .subscript and
                try expressions.inferExpr(allocator, var_types, class_fields, func_return_types, attr.value.subscript.value.*) == .dataframe))
        {
            if (DfColumnMethods.has(attr.attr)) return .float;
            if (fnv_hash.hash(attr.attr) == comptime fnv_hash.hash("describe")) return .unknown;
        }

        // Path methods
        if (obj_type == .path) {
            const method_hash = fnv_hash.hash(attr.attr);
            const PARENT_HASH = comptime fnv_hash.hash("parent");
            const EXISTS_HASH = comptime fnv_hash.hash("exists");
            const IS_FILE_HASH = comptime fnv_hash.hash("is_file");
            const IS_DIR_HASH = comptime fnv_hash.hash("is_dir");
            const READ_TEXT_HASH = comptime fnv_hash.hash("read_text");
            // Methods that return Path
            if (method_hash == PARENT_HASH) return .path;
            // Methods that return bool
            if (method_hash == EXISTS_HASH or method_hash == IS_FILE_HASH or method_hash == IS_DIR_HASH) {
                return .bool;
            }
            // Methods that return string
            if (method_hash == READ_TEXT_HASH) {
                return .{ .string = .runtime };
            }
        }

        // HashObject methods (hashlib)
        if (obj_type == .hash_object) {
            const method_hash = fnv_hash.hash(attr.attr);
            const HEXDIGEST_HASH = comptime fnv_hash.hash("hexdigest");
            const DIGEST_HASH = comptime fnv_hash.hash("digest");
            const COPY_HASH = comptime fnv_hash.hash("copy");
            // hexdigest returns string
            if (method_hash == HEXDIGEST_HASH) return .{ .string = .runtime };
            // digest returns bytes (we represent as string)
            if (method_hash == DIGEST_HASH) return .{ .string = .runtime };
            // copy returns hash_object
            if (method_hash == COPY_HASH) return .hash_object;
            // update returns void (we'll handle as None)
        }
    }

    return .unknown;
}
