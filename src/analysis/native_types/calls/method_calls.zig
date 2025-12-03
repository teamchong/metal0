/// Type inference for method calls (string.upper(), list.append(), etc.)
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

/// Infer type from instance method call (obj.method())
pub fn inferMethodCall(
    allocator: std.mem.Allocator,
    var_types: *FnvHashMap,
    class_fields: *FnvClassMap,
    func_return_types: *FnvHashMap,
    obj_type: NativeType,
    method_name: []const u8,
    call: ast.Node.Call,
) InferError!NativeType {
    _ = var_types;
    _ = class_fields;
    _ = func_return_types;
    // String methods
    if (obj_type == .string) {
        if (static_maps.StringMethods.get(method_name)) |return_type| {
            return return_type;
        }
        if (static_maps.StringBoolMethods.has(method_name)) return .bool;
        if (static_maps.StringIntMethods.has(method_name)) return .{ .int = .bounded };

        // split() returns list of runtime strings
        if (fnv_hash.hash(method_name) == comptime fnv_hash.hash("split")) {
            const elem_ptr = try allocator.create(NativeType);
            elem_ptr.* = .{ .string = .runtime };
            return .{ .list = elem_ptr };
        }
    }

    // List methods (also handle array types since they may be promoted to list later)
    if (obj_type == .list or obj_type == .array) {
        const method_hash = fnv_hash.hash(method_name);
        const POP_HASH = comptime fnv_hash.hash("pop");
        const INDEX_HASH = comptime fnv_hash.hash("index");
        const COUNT_HASH = comptime fnv_hash.hash("count");
        const COPY_HASH = comptime fnv_hash.hash("copy");
        const APPEND_HASH = comptime fnv_hash.hash("append");
        const EXTEND_HASH = comptime fnv_hash.hash("extend");
        const INSERT_HASH = comptime fnv_hash.hash("insert");
        const REMOVE_HASH = comptime fnv_hash.hash("remove");
        const CLEAR_HASH = comptime fnv_hash.hash("clear");
        const SORT_HASH = comptime fnv_hash.hash("sort");
        const REVERSE_HASH = comptime fnv_hash.hash("reverse");

        // Get element type (different access for list vs array)
        const elem_type = if (obj_type == .list) obj_type.list.* else obj_type.array.element_type.*;

        // pop() returns the element type
        if (method_hash == POP_HASH) {
            return elem_type;
        }
        // index() and count() return int
        if (method_hash == INDEX_HASH or method_hash == COUNT_HASH) {
            return .{ .int = .bounded };
        }
        // copy() returns list of same type
        if (method_hash == COPY_HASH) {
            return obj_type;
        }
        // These methods return void/None
        if (method_hash == APPEND_HASH or method_hash == EXTEND_HASH or
            method_hash == INSERT_HASH or method_hash == REMOVE_HASH or
            method_hash == CLEAR_HASH or method_hash == SORT_HASH or
            method_hash == REVERSE_HASH)
        {
            return .none;
        }
    }

    // Dict methods using hash-based dispatch
    if (obj_type == .dict) {
        const method_hash = fnv_hash.hash(method_name);
        const KEYS_HASH = comptime fnv_hash.hash("keys");
        const VALUES_HASH = comptime fnv_hash.hash("values");
        const ITEMS_HASH = comptime fnv_hash.hash("items");
        const GET_HASH = comptime fnv_hash.hash("get");
        const POP_HASH = comptime fnv_hash.hash("pop");
        const SETDEFAULT_HASH = comptime fnv_hash.hash("setdefault");
        const UPDATE_HASH = comptime fnv_hash.hash("update");
        const CLEAR_HASH = comptime fnv_hash.hash("clear");
        const COPY_HASH = comptime fnv_hash.hash("copy");
        const POPITEM_HASH = comptime fnv_hash.hash("popitem");

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
            GET_HASH => {
                // get(key) without default returns optional (could be None)
                // get(key, default) returns the value type (unwrapped by orelse)
                if (call.args.len >= 2) {
                    // Has default - returns unwrapped value type
                    return obj_type.dict.value.*;
                } else {
                    // No default - returns optional (but Python uses None, so we use value type)
                    // The codegen will handle the optional unwrapping
                    return obj_type.dict.value.*;
                }
            },
            POP_HASH, SETDEFAULT_HASH => {
                // pop/setdefault return the value type
                return obj_type.dict.value.*;
            },
            UPDATE_HASH, CLEAR_HASH => {
                // update/clear return None
                return .none;
            },
            COPY_HASH => {
                // copy returns same dict type
                return obj_type;
            },
            POPITEM_HASH => {
                // popitem returns (key, value) tuple
                const tuple_types = try allocator.alloc(NativeType, 2);
                tuple_types[0] = .{ .string = .runtime };
                tuple_types[1] = obj_type.dict.value.*;
                return .{ .tuple = tuple_types };
            },
            else => {},
        }
    }

    // Path methods
    if (obj_type == .path) {
        const method_hash = fnv_hash.hash(method_name);
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
        const method_hash = fnv_hash.hash(method_name);
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

    // SQLite Connection methods
    if (obj_type == .sqlite_connection) {
        const method_hash = fnv_hash.hash(method_name);
        const CURSOR_HASH = comptime fnv_hash.hash("cursor");
        const EXECUTE_HASH = comptime fnv_hash.hash("execute");
        const COMMIT_HASH = comptime fnv_hash.hash("commit");
        const ROLLBACK_HASH = comptime fnv_hash.hash("rollback");
        const CLOSE_HASH = comptime fnv_hash.hash("close");
        if (method_hash == CURSOR_HASH or method_hash == EXECUTE_HASH) return .sqlite_cursor;
        if (method_hash == COMMIT_HASH or method_hash == ROLLBACK_HASH or method_hash == CLOSE_HASH) return .none;
    }

    // SQLite Cursor methods
    if (obj_type == .sqlite_cursor) {
        const method_hash = fnv_hash.hash(method_name);
        const EXECUTE_HASH = comptime fnv_hash.hash("execute");
        const EXECUTEMANY_HASH = comptime fnv_hash.hash("executemany");
        const FETCHONE_HASH = comptime fnv_hash.hash("fetchone");
        const FETCHALL_HASH = comptime fnv_hash.hash("fetchall");
        const FETCHMANY_HASH = comptime fnv_hash.hash("fetchmany");
        const CLOSE_HASH = comptime fnv_hash.hash("close");
        // execute/executemany return none (cursor is modified in place)
        if (method_hash == EXECUTE_HASH or method_hash == EXECUTEMANY_HASH) return .none;
        // fetchone returns a single row
        if (method_hash == FETCHONE_HASH) return .sqlite_row;
        // fetchall/fetchmany return list of rows
        if (method_hash == FETCHALL_HASH or method_hash == FETCHMANY_HASH) return .sqlite_rows;
        if (method_hash == CLOSE_HASH) return .none;
    }

    // StringIO methods
    if (obj_type == .stringio) {
        const method_hash = fnv_hash.hash(method_name);
        const GETVALUE_HASH = comptime fnv_hash.hash("getvalue");
        const READ_HASH = comptime fnv_hash.hash("read");
        const READLINE_HASH = comptime fnv_hash.hash("readline");
        const WRITE_HASH = comptime fnv_hash.hash("write");
        const SEEK_HASH = comptime fnv_hash.hash("seek");
        const TELL_HASH = comptime fnv_hash.hash("tell");
        const CLOSE_HASH = comptime fnv_hash.hash("close");
        // getvalue/read/readline return string
        if (method_hash == GETVALUE_HASH or method_hash == READ_HASH or method_hash == READLINE_HASH) {
            return .{ .string = .runtime };
        }
        // write returns int (bytes written)
        if (method_hash == WRITE_HASH) return .{ .int = .bounded };
        // seek/tell return int
        if (method_hash == SEEK_HASH or method_hash == TELL_HASH) return .{ .int = .bounded };
        // close returns None
        if (method_hash == CLOSE_HASH) return .none;
    }

    // BytesIO methods
    if (obj_type == .bytesio) {
        const method_hash = fnv_hash.hash(method_name);
        const GETVALUE_HASH = comptime fnv_hash.hash("getvalue");
        const READ_HASH = comptime fnv_hash.hash("read");
        const WRITE_HASH = comptime fnv_hash.hash("write");
        const SEEK_HASH = comptime fnv_hash.hash("seek");
        const TELL_HASH = comptime fnv_hash.hash("tell");
        const CLOSE_HASH = comptime fnv_hash.hash("close");
        // getvalue/read return bytes (represented as string)
        if (method_hash == GETVALUE_HASH or method_hash == READ_HASH) {
            return .{ .string = .runtime };
        }
        // write returns int (bytes written)
        if (method_hash == WRITE_HASH) return .{ .int = .bounded };
        // seek/tell return int
        if (method_hash == SEEK_HASH or method_hash == TELL_HASH) return .{ .int = .bounded };
        // close returns None
        if (method_hash == CLOSE_HASH) return .none;
    }

    return .unknown;
}
