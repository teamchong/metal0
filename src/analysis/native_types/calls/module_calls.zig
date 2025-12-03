/// Type inference for module function calls (json.dumps, math.sqrt, np.array, etc.)
const std = @import("std");
const ast = @import("ast");
const core = @import("../core.zig");
const fnv_hash = @import("fnv_hash");
const static_maps = @import("static_maps.zig");
const expressions = @import("../expressions.zig");

pub const NativeType = core.NativeType;
pub const InferError = core.InferError;

const hashmap_helper = @import("hashmap_helper");
const FnvHashMap = hashmap_helper.StringHashMap(NativeType);
const FnvClassMap = hashmap_helper.StringHashMap(core.ClassInfo);

/// Infer type from module function call (module.func())
pub fn inferModuleFunctionCall(
    allocator: std.mem.Allocator,
    var_types: *FnvHashMap,
    class_fields: *FnvClassMap,
    func_return_types: *FnvHashMap,
    module_name: []const u8,
    func_name: []const u8,
) InferError!NativeType {
    _ = var_types;
    _ = class_fields;
    _ = func_return_types;
    // Module function dispatch using hash for module name
    const module_hash = fnv_hash.hash(module_name);
    const JSON_HASH = comptime fnv_hash.hash("json");
    const MATH_HASH = comptime fnv_hash.hash("math");
    const IO_HASH = comptime fnv_hash.hash("io");
    const HASHLIB_HASH = comptime fnv_hash.hash("hashlib");
    const STRUCT_HASH = comptime fnv_hash.hash("struct");
    const BASE64_HASH = comptime fnv_hash.hash("base64");
    const PICKLE_HASH = comptime fnv_hash.hash("pickle");
    const HMAC_HASH = comptime fnv_hash.hash("hmac");
    const SOCKET_HASH = comptime fnv_hash.hash("socket");
    const OS_HASH = comptime fnv_hash.hash("os");
    const OS_PATH_HASH = comptime fnv_hash.hash("os.path");
    const PATH_HASH = comptime fnv_hash.hash("path");
    const RANDOM_HASH = comptime fnv_hash.hash("random");
    const TIME_HASH = comptime fnv_hash.hash("time");
    const UUID_HASH = comptime fnv_hash.hash("uuid");
    const THREADING_HASH = comptime fnv_hash.hash("threading");
    const SQLITE3_HASH = comptime fnv_hash.hash("sqlite3");
    const ZLIB_HASH = comptime fnv_hash.hash("zlib");
    const GZIP_HASH = comptime fnv_hash.hash("gzip");
    const RE_HASH = comptime fnv_hash.hash("re");
    const _STRING_HASH = comptime fnv_hash.hash("_string");

    switch (module_hash) {
        SQLITE3_HASH => {
            // sqlite3 module type inference
            const func_hash = fnv_hash.hash(func_name);
            const CONNECT_HASH = comptime fnv_hash.hash("connect");
            if (func_hash == CONNECT_HASH) return .sqlite_connection;
            return .unknown;
        },
        ZLIB_HASH => {
            // zlib compress/decompress returns bytes (string)
            const func_hash = fnv_hash.hash(func_name);
            const COMPRESS_HASH = comptime fnv_hash.hash("compress");
            const DECOMPRESS_HASH = comptime fnv_hash.hash("decompress");
            const CRC32_HASH = comptime fnv_hash.hash("crc32");
            const ADLER32_HASH = comptime fnv_hash.hash("adler32");
            if (func_hash == COMPRESS_HASH or func_hash == DECOMPRESS_HASH) {
                return .{ .string = .runtime };
            }
            if (func_hash == CRC32_HASH or func_hash == ADLER32_HASH) {
                return .{ .int = .bounded };
            }
            return .unknown;
        },
        GZIP_HASH => {
            // gzip compress/decompress returns bytes (string)
            const func_hash = fnv_hash.hash(func_name);
            const COMPRESS_HASH = comptime fnv_hash.hash("compress");
            const DECOMPRESS_HASH = comptime fnv_hash.hash("decompress");
            if (func_hash == COMPRESS_HASH or func_hash == DECOMPRESS_HASH) {
                return .{ .string = .runtime };
            }
            return .unknown;
        },
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
                return .{ .int = .bounded };
            }
            return .none; // setdefaulttimeout, etc.
        },
        OS_HASH => {
            // os module type inference
            const func_hash = fnv_hash.hash(func_name);
            const GETCWD_HASH = comptime fnv_hash.hash("getcwd");
            const LISTDIR_HASH = comptime fnv_hash.hash("listdir");
            const CHDIR_HASH = comptime fnv_hash.hash("chdir");
            const GETENV_HASH = comptime fnv_hash.hash("getenv");
            const MKDIR_HASH = comptime fnv_hash.hash("mkdir");
            const MAKEDIRS_HASH = comptime fnv_hash.hash("makedirs");
            if (func_hash == GETCWD_HASH or func_hash == GETENV_HASH) return .{ .string = .runtime };
            if (func_hash == LISTDIR_HASH) return .unknown; // ArrayList([]const u8)
            if (func_hash == CHDIR_HASH or func_hash == MKDIR_HASH or func_hash == MAKEDIRS_HASH) return .none;
            return .unknown;
        },
        OS_PATH_HASH, PATH_HASH => {
            // os.path module type inference
            const func_hash = fnv_hash.hash(func_name);
            const EXISTS_HASH = comptime fnv_hash.hash("exists");
            const ISFILE_HASH = comptime fnv_hash.hash("isfile");
            const ISDIR_HASH = comptime fnv_hash.hash("isdir");
            const JOIN_HASH = comptime fnv_hash.hash("join");
            const DIRNAME_HASH = comptime fnv_hash.hash("dirname");
            const BASENAME_HASH = comptime fnv_hash.hash("basename");
            const SPLIT_HASH_OS = comptime fnv_hash.hash("split");
            const SPLITEXT_HASH = comptime fnv_hash.hash("splitext");
            if (func_hash == EXISTS_HASH or func_hash == ISFILE_HASH or func_hash == ISDIR_HASH) {
                return .bool;
            }
            if (func_hash == JOIN_HASH or func_hash == DIRNAME_HASH or func_hash == BASENAME_HASH) {
                return .{ .string = .runtime };
            }
            // os.path.split() and splitext() return tuple of (string, string)
            if (func_hash == SPLIT_HASH_OS or func_hash == SPLITEXT_HASH) {
                const tuple_elems = try allocator.alloc(NativeType, 2);
                tuple_elems[0] = .{ .string = .runtime };
                tuple_elems[1] = .{ .string = .runtime };
                return .{ .tuple = tuple_elems };
            }
            return .unknown;
        },
        RANDOM_HASH => {
            // random module type inference
            const func_hash = fnv_hash.hash(func_name);
            const RANDOM_FN_HASH = comptime fnv_hash.hash("random");
            const UNIFORM_HASH = comptime fnv_hash.hash("uniform");
            const GAUSS_HASH = comptime fnv_hash.hash("gauss");
            const RANDINT_HASH = comptime fnv_hash.hash("randint");
            const RANDRANGE_HASH = comptime fnv_hash.hash("randrange");
            const GETRANDBITS_HASH = comptime fnv_hash.hash("getrandbits");
            const SEED_HASH = comptime fnv_hash.hash("seed");
            const CHOICE_HASH = comptime fnv_hash.hash("choice");
            const SHUFFLE_HASH = comptime fnv_hash.hash("shuffle");
            const SAMPLE_HASH = comptime fnv_hash.hash("sample");
            const CHOICES_HASH = comptime fnv_hash.hash("choices");
            // Float-returning functions
            if (func_hash == RANDOM_FN_HASH or func_hash == UNIFORM_HASH or func_hash == GAUSS_HASH) {
                return .float;
            }
            // Int-returning functions
            if (func_hash == RANDINT_HASH or func_hash == RANDRANGE_HASH or func_hash == GETRANDBITS_HASH) {
                return .{ .int = .bounded };
            }
            // Void-returning functions
            if (func_hash == SEED_HASH or func_hash == SHUFFLE_HASH) {
                return .none;
            }
            // choice returns element type (assume int for common case)
            if (func_hash == CHOICE_HASH) {
                return .{ .int = .bounded };
            }
            // sample/choices return list (unknown for now)
            if (func_hash == SAMPLE_HASH or func_hash == CHOICES_HASH) {
                return .unknown;
            }
            return .unknown;
        },
        TIME_HASH => {
            // time module type inference
            const func_hash = fnv_hash.hash(func_name);
            const TIME_FN_HASH = comptime fnv_hash.hash("time");
            const SLEEP_HASH = comptime fnv_hash.hash("sleep");
            const CTIME_HASH = comptime fnv_hash.hash("ctime");
            const STRFTIME_HASH = comptime fnv_hash.hash("strftime");
            const LOCALTIME_HASH = comptime fnv_hash.hash("localtime");
            const GMTIME_HASH = comptime fnv_hash.hash("gmtime");
            const PERF_COUNTER_HASH = comptime fnv_hash.hash("perf_counter");
            const MONOTONIC_HASH = comptime fnv_hash.hash("monotonic");
            if (func_hash == TIME_FN_HASH or func_hash == PERF_COUNTER_HASH or func_hash == MONOTONIC_HASH) {
                return .float;
            }
            if (func_hash == SLEEP_HASH) return .none;
            if (func_hash == CTIME_HASH or func_hash == STRFTIME_HASH) return .{ .string = .runtime };
            if (func_hash == LOCALTIME_HASH or func_hash == GMTIME_HASH) return .unknown; // struct_time
            return .unknown;
        },
        UUID_HASH => {
            // uuid module type inference
            const func_hash = fnv_hash.hash(func_name);
            const UUID1_HASH = comptime fnv_hash.hash("uuid1");
            const UUID3_HASH = comptime fnv_hash.hash("uuid3");
            const UUID4_HASH = comptime fnv_hash.hash("uuid4");
            const UUID5_HASH = comptime fnv_hash.hash("uuid5");
            if (func_hash == UUID1_HASH or func_hash == UUID3_HASH or
                func_hash == UUID4_HASH or func_hash == UUID5_HASH)
            {
                return .{ .string = .runtime }; // UUID as string
            }
            return .unknown;
        },
        THREADING_HASH => {
            // threading module type inference
            const func_hash = fnv_hash.hash(func_name);
            const ACTIVE_COUNT_HASH = comptime fnv_hash.hash("active_count");
            if (func_hash == ACTIVE_COUNT_HASH) {
                return .{ .int = .bounded };
            }
            return .unknown; // Thread, Lock, Event etc. are structs
        },
        fnv_hash.hash("statistics") => {
            // statistics module - most functions return float
            const func_hash = fnv_hash.hash(func_name);
            const MEAN_HASH = comptime fnv_hash.hash("mean");
            const FMEAN_HASH = comptime fnv_hash.hash("fmean");
            const MEDIAN_HASH = comptime fnv_hash.hash("median");
            const STDEV_HASH = comptime fnv_hash.hash("stdev");
            const PSTDEV_HASH = comptime fnv_hash.hash("pstdev");
            const VARIANCE_HASH = comptime fnv_hash.hash("variance");
            const PVARIANCE_HASH = comptime fnv_hash.hash("pvariance");
            const GEOMETRIC_MEAN_HASH = comptime fnv_hash.hash("geometric_mean");
            const HARMONIC_MEAN_HASH = comptime fnv_hash.hash("harmonic_mean");
            if (func_hash == MEAN_HASH or func_hash == FMEAN_HASH or
                func_hash == MEDIAN_HASH or func_hash == STDEV_HASH or
                func_hash == PSTDEV_HASH or func_hash == VARIANCE_HASH or
                func_hash == PVARIANCE_HASH or func_hash == GEOMETRIC_MEAN_HASH or
                func_hash == HARMONIC_MEAN_HASH)
            {
                return .float;
            }
            return .unknown;
        },
        fnv_hash.hash("bisect") => {
            // bisect module - bisect_left/right/bisect return int, insort returns None
            const func_hash = fnv_hash.hash(func_name);
            const BISECT_LEFT_HASH = comptime fnv_hash.hash("bisect_left");
            const BISECT_RIGHT_HASH = comptime fnv_hash.hash("bisect_right");
            const BISECT_HASH = comptime fnv_hash.hash("bisect");
            const INSORT_LEFT_HASH = comptime fnv_hash.hash("insort_left");
            const INSORT_RIGHT_HASH = comptime fnv_hash.hash("insort_right");
            const INSORT_HASH = comptime fnv_hash.hash("insort");
            if (func_hash == BISECT_LEFT_HASH or
                func_hash == BISECT_RIGHT_HASH or
                func_hash == BISECT_HASH)
            {
                return .{ .int = .bounded };
            }
            if (func_hash == INSORT_LEFT_HASH or
                func_hash == INSORT_RIGHT_HASH or
                func_hash == INSORT_HASH)
            {
                return .none;
            }
            return .unknown;
        },
        fnv_hash.hash("textwrap") => {
            // textwrap module
            const func_hash = fnv_hash.hash(func_name);
            const WRAP_HASH = comptime fnv_hash.hash("wrap");
            const FILL_HASH = comptime fnv_hash.hash("fill");
            const DEDENT_HASH = comptime fnv_hash.hash("dedent");
            const INDENT_HASH = comptime fnv_hash.hash("indent");
            const SHORTEN_HASH = comptime fnv_hash.hash("shorten");
            // wrap returns list of strings (list type for .len support)
            if (func_hash == WRAP_HASH) {
                return .{ .list = @constCast(&NativeType{ .string = .slice }) };
            }
            if (func_hash == FILL_HASH or func_hash == DEDENT_HASH or
                func_hash == INDENT_HASH or func_hash == SHORTEN_HASH)
            {
                return .{ .string = .runtime };
            }
            return .unknown;
        },
        fnv_hash.hash("heapq") => {
            // heapq module
            const func_hash = fnv_hash.hash(func_name);
            const HEAPIFY_HASH = comptime fnv_hash.hash("heapify");
            const HEAPPUSH_HASH = comptime fnv_hash.hash("heappush");
            const HEAPPOP_HASH = comptime fnv_hash.hash("heappop");
            const HEAPREPLACE_HASH = comptime fnv_hash.hash("heapreplace");
            const HEAPPUSHPOP_HASH = comptime fnv_hash.hash("heappushpop");
            if (func_hash == HEAPIFY_HASH or func_hash == HEAPPUSH_HASH) {
                return .none;
            }
            if (func_hash == HEAPPOP_HASH or func_hash == HEAPREPLACE_HASH or
                func_hash == HEAPPUSHPOP_HASH)
            {
                return .{ .int = .bounded }; // Returns element from heap
            }
            return .unknown; // nlargest/nsmallest returns list
        },
        fnv_hash.hash("functools") => {
            // functools module - reduce returns element type
            const func_hash = fnv_hash.hash(func_name);
            const REDUCE_HASH = comptime fnv_hash.hash("reduce");
            const PARTIAL_HASH = comptime fnv_hash.hash("partial");
            const CACHE_HASH = comptime fnv_hash.hash("cache");
            const LRU_CACHE_HASH = comptime fnv_hash.hash("lru_cache");
            if (func_hash == REDUCE_HASH) {
                return .{ .int = .bounded }; // Most common use is numeric reduction
            }
            if (func_hash == PARTIAL_HASH or func_hash == CACHE_HASH or
                func_hash == LRU_CACHE_HASH)
            {
                return .unknown; // Returns decorated function
            }
            return .unknown;
        },
        fnv_hash.hash("operator") => {
            // operator module - math ops return int/float
            const func_hash = fnv_hash.hash(func_name);
            const ADD_HASH = comptime fnv_hash.hash("add");
            const SUB_HASH = comptime fnv_hash.hash("sub");
            const MUL_HASH = comptime fnv_hash.hash("mul");
            const TRUEDIV_HASH = comptime fnv_hash.hash("truediv");
            const FLOORDIV_HASH = comptime fnv_hash.hash("floordiv");
            const MOD_HASH = comptime fnv_hash.hash("mod");
            const POW_HASH = comptime fnv_hash.hash("pow");
            const NEG_HASH = comptime fnv_hash.hash("neg");
            const ABS_HASH = comptime fnv_hash.hash("abs");
            if (func_hash == ADD_HASH or func_hash == SUB_HASH or
                func_hash == MUL_HASH or func_hash == FLOORDIV_HASH or
                func_hash == MOD_HASH or func_hash == POW_HASH or
                func_hash == NEG_HASH or func_hash == ABS_HASH)
            {
                return .{ .int = .bounded };
            }
            if (func_hash == TRUEDIV_HASH) {
                return .float;
            }
            return .unknown;
        },
        fnv_hash.hash("copy") => {
            // copy module - returns same type as input (unknown)
            return .unknown;
        },
        fnv_hash.hash("fnmatch") => {
            // fnmatch module - fnmatch/fnmatchcase return bool, filter returns list
            const func_hash = fnv_hash.hash(func_name);
            const FNMATCH_HASH = comptime fnv_hash.hash("fnmatch");
            const FNMATCHCASE_HASH = comptime fnv_hash.hash("fnmatchcase");
            const FILTER_HASH = comptime fnv_hash.hash("filter");
            const TRANSLATE_HASH = comptime fnv_hash.hash("translate");
            if (func_hash == FNMATCH_HASH or func_hash == FNMATCHCASE_HASH) {
                return .bool;
            }
            if (func_hash == FILTER_HASH) {
                return .{ .list = @constCast(&NativeType{ .string = .slice }) };
            }
            if (func_hash == TRANSLATE_HASH) {
                return .{ .string = .runtime };
            }
            return .unknown;
        },
        fnv_hash.hash("glob") => {
            // glob module - glob/iglob return list of strings
            const func_hash = fnv_hash.hash(func_name);
            const GLOB_HASH = comptime fnv_hash.hash("glob");
            const IGLOB_HASH = comptime fnv_hash.hash("iglob");
            const ESCAPE_HASH = comptime fnv_hash.hash("escape");
            const HAS_MAGIC_HASH = comptime fnv_hash.hash("has_magic");
            if (func_hash == GLOB_HASH or func_hash == IGLOB_HASH) {
                return .{ .list = @constCast(&NativeType{ .string = .slice }) };
            }
            if (func_hash == ESCAPE_HASH) {
                return .{ .string = .runtime };
            }
            if (func_hash == HAS_MAGIC_HASH) {
                return .bool;
            }
            return .unknown;
        },
        fnv_hash.hash("calendar") => {
            // calendar module
            const func_hash = fnv_hash.hash(func_name);
            const ISLEAP_HASH = comptime fnv_hash.hash("isleap");
            const LEAPDAYS_HASH = comptime fnv_hash.hash("leapdays");
            const WEEKDAY_HASH = comptime fnv_hash.hash("weekday");
            const MONTHRANGE_HASH = comptime fnv_hash.hash("monthrange");
            const MONTH_HASH = comptime fnv_hash.hash("month");
            const CALENDAR_HASH = comptime fnv_hash.hash("calendar");
            if (func_hash == ISLEAP_HASH) {
                return .bool;
            }
            if (func_hash == LEAPDAYS_HASH or func_hash == WEEKDAY_HASH) {
                return .{ .int = .bounded };
            }
            if (func_hash == MONTHRANGE_HASH) {
                // Returns (first_weekday, num_days) tuple
                return .{ .tuple = &[_]NativeType{ .{ .int = .bounded }, .{ .int = .bounded } } };
            }
            if (func_hash == MONTH_HASH or func_hash == CALENDAR_HASH) {
                return .{ .string = .runtime };
            }
            return .unknown;
        },
        fnv_hash.hash("tempfile") => {
            // tempfile module
            const func_hash = fnv_hash.hash(func_name);
            const GETTEMPDIR_HASH = comptime fnv_hash.hash("gettempdir");
            const GETTEMPPREFIX_HASH = comptime fnv_hash.hash("gettempprefix");
            const MKSTEMP_HASH = comptime fnv_hash.hash("mkstemp");
            const MKDTEMP_HASH = comptime fnv_hash.hash("mkdtemp");
            if (func_hash == GETTEMPDIR_HASH or func_hash == GETTEMPPREFIX_HASH or
                func_hash == MKDTEMP_HASH)
            {
                return .{ .string = .runtime };
            }
            if (func_hash == MKSTEMP_HASH) {
                return .{ .tuple = &[_]NativeType{ .{ .int = .bounded }, .{ .string = .runtime } } }; // Returns (fd, name) tuple
            }
            return .unknown;
        },
        fnv_hash.hash("gc") => {
            // gc module
            const func_hash = fnv_hash.hash(func_name);
            const COLLECT_HASH = comptime fnv_hash.hash("collect");
            const ISENABLED_HASH = comptime fnv_hash.hash("isenabled");
            const ENABLE_HASH = comptime fnv_hash.hash("enable");
            const DISABLE_HASH = comptime fnv_hash.hash("disable");
            if (func_hash == COLLECT_HASH) {
                return .{ .int = .bounded };
            }
            if (func_hash == ISENABLED_HASH) {
                return .bool;
            }
            if (func_hash == ENABLE_HASH or func_hash == DISABLE_HASH) {
                return .none;
            }
            return .unknown;
        },
        fnv_hash.hash("collections") => {
            // collections module
            const func_hash = fnv_hash.hash(func_name);
            const COUNTER_HASH = comptime fnv_hash.hash("Counter");
            const DEQUE_HASH = comptime fnv_hash.hash("deque");
            if (func_hash == COUNTER_HASH) return .counter;
            if (func_hash == DEQUE_HASH) return .deque;
            return .unknown;
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
            if (func_hash == CALCSIZE_HASH) return .{ .int = .bounded };
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
        JSON_HASH => {
            // json.dumps() returns string, json.loads() returns dynamic
            const func_hash = fnv_hash.hash(func_name);
            if (func_hash == comptime fnv_hash.hash("dumps")) return .{ .string = .runtime };
            if (func_hash == comptime fnv_hash.hash("loads")) return .unknown;
            return .unknown;
        },
        RE_HASH => {
            // re module functions all return *runtime.PyObject
            // match/search return Match or None, findall/split return PyList,
            // sub returns PyString - all are PyObject pointers
            return .unknown; // All re funcs return *runtime.PyObject
        },
        _STRING_HASH => {
            // _string module (internal string formatting)
            const func_hash = fnv_hash.hash(func_name);
            if (func_hash == comptime fnv_hash.hash("formatter_parser")) {
                // Returns list of tuples: [(literal, field_name, format_spec, conversion), ...]
                // Each tuple element is optional string
                const inner = allocator.create(NativeType) catch return .unknown;
                inner.* = .{ .string = .runtime };
                const opt_str = allocator.create(NativeType) catch return .unknown;
                opt_str.* = .{ .optional = inner };
                const tuple_types = allocator.alloc(NativeType, 4) catch return .unknown;
                tuple_types[0] = .{ .string = .runtime };
                tuple_types[1] = .{ .optional = inner };
                tuple_types[2] = .{ .optional = inner };
                tuple_types[3] = .{ .optional = inner };
                const tuple_ptr = allocator.create(NativeType) catch return .unknown;
                tuple_ptr.* = .{ .tuple = tuple_types };
                return .{ .list = tuple_ptr };
            }
            if (func_hash == comptime fnv_hash.hash("formatter_field_name_split")) {
                // Returns (first: str, rest: list) tuple
                // Using tuple type so list() conversion will use PyValue
                var tuple_types = allocator.alloc(NativeType, 2) catch return .unknown;
                tuple_types[0] = .{ .string = .runtime };
                const elem_ptr = allocator.create(NativeType) catch return .unknown;
                elem_ptr.* = .{ .tuple = &[_]NativeType{ .bool, .{ .string = .runtime } } };
                tuple_types[1] = .{ .list = elem_ptr };
                return .{ .tuple = tuple_types };
            }
            return .unknown;
        },
        MATH_HASH => {
            if (static_maps.MathIntFuncs.has(func_name)) return .{ .int = .bounded };
            if (static_maps.MathBoolFuncs.has(func_name)) return .bool;
            return .float; // All other math functions return float
        },
        else => {},
    }

    return .unknown;
}
