/// metal0 unittest assertions - assertEqual function
const std = @import("std");
const allocator_helper = @import("utils.allocator_helper");
const runner = @import("../../unittest/runner.zig");
const runtime = @import("../../../runtime.zig");
const helpers = @import("equality_helpers.zig");

const equalArrayList = helpers.equalArrayList;
const equalHashMap = helpers.equalHashMap;
const equalPyValueWith = helpers.equalPyValueWith;
const equalTuples = helpers.equalTuples;
const equalValues = helpers.equalValues;
const elemEql = helpers.elemEql;
const isStringType = helpers.isStringType;

/// Assertion: assertEqual(a, b) - values must be equal
pub fn assertEqual(a: anytype, b: anytype) !void {
    const A = @TypeOf(a);
    const B = @TypeOf(b);
    const a_info = @typeInfo(A);
    const b_info = @typeInfo(B);

    // Handle optional comparisons (for dict.get() etc)
    // Case 1: Both are optional - compare directly
    if (a_info == .optional and b_info == .optional) {
        const a_is_null = a == null;
        const b_is_null = b == null;
        if (a_is_null and b_is_null) {
            // Both null - equal
            if (runner.global_result) |result| {
                result.addPass();
            }
            return;
        } else if (a_is_null or b_is_null) {
            // One null, one not - not equal
            std.debug.print("AssertionError: {any} != {any}\n", .{ a, b });
            if (runner.global_result) |result| {
                result.addFail("assertEqual failed") catch {};
            }
            return error.AssertionFailed;
        } else {
            // Both non-null - compare unwrapped values
            return try assertEqual(a.?, b.?);
        }
    }
    // Case 2: Optional compared with null literal type (assertEqual(d.get(x), None))
    if (a_info == .optional and b_info == .null) {
        if (a == null) {
            // a is null, b is null literal - equal
            if (runner.global_result) |result| {
                result.addPass();
            }
            return;
        } else {
            // a has value, b is null - not equal
            std.debug.print("AssertionError: {any} != null\n", .{a});
            if (runner.global_result) |result| {
                result.addFail("assertEqual failed") catch {};
            }
            return error.AssertionFailed;
        }
    }
    if (a_info == .null and b_info == .optional) {
        if (b == null) {
            // a is null literal, b is null - equal
            if (runner.global_result) |result| {
                result.addPass();
            }
            return;
        } else {
            // a is null, b has value - not equal
            std.debug.print("AssertionError: null != {any}\n", .{b});
            if (runner.global_result) |result| {
                result.addFail("assertEqual failed") catch {};
            }
            return error.AssertionFailed;
        }
    }
    // Both are null literal type
    if (a_info == .null and b_info == .null) {
        // null == null - equal
        if (runner.global_result) |result| {
            result.addPass();
        }
        return;
    }
    // Case 3: Only 'a' is optional - unwrap and compare
    if (a_info == .optional and b_info != .optional) {
        if (a) |unwrapped| {
            return try assertEqual(unwrapped, b);
        } else {
            // a is null, b is not optional - they can't be equal unless b is null-like
            std.debug.print("AssertionError: {any} != {any}\n", .{ a, b });
            if (runner.global_result) |result| {
                result.addFail("assertEqual failed") catch {};
            }
            return error.AssertionFailed;
        }
    }
    // Case 4: Only 'b' is optional - unwrap and compare
    if (b_info == .optional and a_info != .optional) {
        if (b) |unwrapped| {
            return try assertEqual(a, unwrapped);
        } else {
            // b is null, a is not optional - they can't be equal unless a is null-like
            std.debug.print("AssertionError: {any} != {any}\n", .{ a, b });
            if (runner.global_result) |result| {
                result.addFail("assertEqual failed") catch {};
            }
            return error.AssertionFailed;
        }
    }

    // Unwrap error unions before comparison
    if (a_info == .error_union) {
        const unwrapped = a catch {
            std.debug.print("AssertionError: first argument is error\n", .{});
            if (runner.global_result) |result| {
                result.addFail("assertEqual failed - error value") catch {};
            }
            return error.AssertionFailed;
        };
        return try assertEqual(unwrapped, b);
    }
    if (b_info == .error_union) {
        const unwrapped = b catch {
            std.debug.print("AssertionError: second argument is error\n", .{});
            if (runner.global_result) |result| {
                result.addFail("assertEqual failed - error value") catch {};
            }
            return error.AssertionFailed;
        };
        return try assertEqual(a, unwrapped);
    }

    // =========================================================================
    // FAST PATHS for common concrete types (reduces monomorphization)
    // These dispatch to comparison_ops which compile ONCE, not per call site
    // =========================================================================
    const comparison_ops = runtime.comparison_ops;

    // Fast path: PyValue == PyValue (most common for uncertain types)
    if (A == runtime.PyValue and B == runtime.PyValue) {
        if (comparison_ops.eqPyValue(a, b)) {
            if (runner.global_result) |result| result.addPass();
            return;
        }
        std.debug.print("AssertionError: {any} != {any}\n", .{ a, b });
        if (runner.global_result) |result| result.addFail("assertEqual failed") catch {};
        return error.AssertionFailed;
    }

    // Fast path: i64 == i64
    if (A == i64 and B == i64) {
        if (comparison_ops.eqI64(a, b)) {
            if (runner.global_result) |result| result.addPass();
            return;
        }
        std.debug.print("AssertionError: {d} != {d}\n", .{ a, b });
        if (runner.global_result) |result| result.addFail("assertEqual failed") catch {};
        return error.AssertionFailed;
    }

    // Fast path: f64 == f64 (with tolerance)
    if (A == f64 and B == f64) {
        const equal = blk: {
            if (std.math.isInf(a) and std.math.isInf(b)) break :blk (a > 0) == (b > 0);
            if (std.math.isNan(a) or std.math.isNan(b)) break :blk false;
            break :blk @abs(a - b) < 0.0001;
        };
        if (equal) {
            if (runner.global_result) |result| result.addPass();
            return;
        }
        std.debug.print("AssertionError: {d} != {d}\n", .{ a, b });
        if (runner.global_result) |result| result.addFail("assertEqual failed") catch {};
        return error.AssertionFailed;
    }

    // Fast path: bool == bool
    if (A == bool and B == bool) {
        if (comparison_ops.eqBool(a, b)) {
            if (runner.global_result) |result| result.addPass();
            return;
        }
        std.debug.print("AssertionError: {} != {}\n", .{ a, b });
        if (runner.global_result) |result| result.addFail("assertEqual failed") catch {};
        return error.AssertionFailed;
    }

    // Fast path: []const u8 == []const u8 (strings)
    if (A == []const u8 and B == []const u8) {
        if (comparison_ops.eqStr(a, b)) {
            if (runner.global_result) |result| result.addPass();
            return;
        }
        std.debug.print("AssertionError: {s} != {s}\n", .{ a, b });
        if (runner.global_result) |result| result.addFail("assertEqual failed") catch {};
        return error.AssertionFailed;
    }

    // Fast path: i64 == f64 (cross-type numeric)
    if (A == i64 and B == f64) {
        if (comparison_ops.eqI64F64(a, b)) {
            if (runner.global_result) |result| result.addPass();
            return;
        }
        std.debug.print("AssertionError: {d} != {d}\n", .{ a, b });
        if (runner.global_result) |result| result.addFail("assertEqual failed") catch {};
        return error.AssertionFailed;
    }
    if (A == f64 and B == i64) {
        if (comparison_ops.eqF64I64(a, b)) {
            if (runner.global_result) |result| result.addPass();
            return;
        }
        std.debug.print("AssertionError: {d} != {d}\n", .{ a, b });
        if (runner.global_result) |result| result.addFail("assertEqual failed") catch {};
        return error.AssertionFailed;
    }

    // =========================================================================
    // End of fast paths - continue with complex type handling
    // =========================================================================

    // Unwrap PyObject pointers before comparison
    if (A == *runtime.PyObject) {
        const py_val = runtime.pyObjectToValue(a);
        return try assertEqual(py_val, b);
    }
    if (B == *runtime.PyObject) {
        const py_val = runtime.pyObjectToValue(b);
        return try assertEqual(a, py_val);
    }

    // Unwrap PyBytes wrapper - compare data field with []const u8
    if (A == runtime.builtins.PyBytes) {
        return try assertEqual(a.data, b);
    }
    if (B == runtime.builtins.PyBytes) {
        return try assertEqual(a, b.data);
    }

    // Unwrap PyPowResult unions - extract float_val for comparison
    if (A == runtime.PyPowResult) {
        switch (a) {
            .float_val => |fv| return try assertEqual(fv, b),
            .complex_val => |cv| {
                // For complex, only equal to another complex or a real number if imag is 0
                if (cv.imag == 0.0) {
                    return try assertEqual(cv.real, b);
                }
                // Complex with non-zero imag part - compare as struct
            },
        }
    }
    if (B == runtime.PyPowResult) {
        switch (b) {
            .float_val => |fv| return try assertEqual(a, fv),
            .complex_val => |cv| {
                if (cv.imag == 0.0) {
                    return try assertEqual(a, cv.real);
                }
            },
        }
    }

    // Unwrap FloorCeilResult unions - extract int or float value for comparison
    if (A == runtime.FloorCeilResult) {
        switch (a) {
            .int => |iv| return try assertEqual(iv, b),
            .float => |fv| return try assertEqual(fv, b),
        }
    }
    if (B == runtime.FloorCeilResult) {
        switch (b) {
            .int => |iv| return try assertEqual(a, iv),
            .float => |fv| return try assertEqual(a, fv),
        }
    }

    // Unwrap IntResult unions - for __floor__/__ceil__ with large floats
    if (A == runtime.IntResult) {
        if (b_info == .float or b_info == .comptime_float) {
            const b_float: f64 = if (b_info == .comptime_float) @as(f64, b) else b;
            if (a.eqlFloat(b_float)) {
                if (runner.global_result) |result| {
                    result.addPass();
                }
                return;
            } else {
                std.debug.print("AssertionError: IntResult({any}) != {d}\n", .{ a, b_float });
                if (runner.global_result) |result| {
                    result.addFail("assertEqual failed") catch {};
                }
                return error.AssertionFailed;
            }
        }
        if (b_info == .int or b_info == .comptime_int) {
            const b_int: i64 = @intCast(b);
            if (a.eqlInt(b_int)) {
                if (runner.global_result) |result| {
                    result.addPass();
                }
                return;
            } else {
                std.debug.print("AssertionError: IntResult({any}) != {d}\n", .{ a, b_int });
                if (runner.global_result) |result| {
                    result.addFail("assertEqual failed") catch {};
                }
                return error.AssertionFailed;
            }
        }
    }
    if (B == runtime.IntResult) {
        if (a_info == .float or a_info == .comptime_float) {
            const a_float: f64 = if (a_info == .comptime_float) @as(f64, a) else a;
            if (b.eqlFloat(a_float)) {
                if (runner.global_result) |result| {
                    result.addPass();
                }
                return;
            } else {
                std.debug.print("AssertionError: {d} != IntResult({any})\n", .{ a_float, b });
                if (runner.global_result) |result| {
                    result.addFail("assertEqual failed") catch {};
                }
                return error.AssertionFailed;
            }
        }
        if (a_info == .int or a_info == .comptime_int) {
            const a_int: i64 = @intCast(a);
            if (b.eqlInt(a_int)) {
                if (runner.global_result) |result| {
                    result.addPass();
                }
                return;
            } else {
                std.debug.print("AssertionError: {d} != IntResult({any})\n", .{ a_int, b });
                if (runner.global_result) |result| {
                    result.addFail("assertEqual failed") catch {};
                }
                return error.AssertionFailed;
            }
        }
    }

    // Handle AutoHashMap (set) comparison
    if (a_info == .@"struct" and b_info == .@"struct") {
        const a_is_hashmap = @hasField(A, "unmanaged") and @hasField(A, "allocator");
        const b_is_hashmap = @hasField(B, "unmanaged") and @hasField(B, "allocator");
        if (a_is_hashmap and b_is_hashmap) {
            const a_key_type = if (@hasDecl(A, "Key")) A.Key else if (@hasDecl(A, "KV")) @typeInfo(A.KV).@"struct".fields[0].type else void;
            const b_key_type = if (@hasDecl(B, "Key")) B.Key else if (@hasDecl(B, "KV")) @typeInfo(B.KV).@"struct".fields[0].type else void;
            if (a_key_type != b_key_type) {
                std.debug.print("AssertionError: maps have different key types\n", .{});
                if (runner.global_result) |result| {
                    result.addFail("assertEqual failed") catch {};
                }
                return error.AssertionFailed;
            }
            const a_count = a.count();
            const b_count = b.count();
            if (a_count != b_count) {
                std.debug.print("AssertionError: sets have different sizes ({d} != {d})\n", .{ a_count, b_count });
                if (runner.global_result) |result| {
                    result.addFail("assertEqual failed") catch {};
                }
                return error.AssertionFailed;
            }
            var all_match = true;
            if (@hasDecl(@TypeOf(a), "keyIterator")) {
                var key_iter = a.keyIterator();
                while (key_iter.next()) |key_ptr| {
                    if (!b.contains(key_ptr.*)) {
                        all_match = false;
                        break;
                    }
                }
            } else if (@hasDecl(@TypeOf(a), "keys")) {
                for (a.keys()) |key| {
                    if (!b.contains(key)) {
                        all_match = false;
                        break;
                    }
                }
            }
            if (!all_match) {
                std.debug.print("AssertionError: sets have different contents\n", .{});
                if (runner.global_result) |result| {
                    result.addFail("assertEqual failed") catch {};
                }
                return error.AssertionFailed;
            }
            return;
        }
    }

    const equal = blk: {
        // Same type - direct comparison
        if (A == B) {
            if (a_info == .float or a_info == .comptime_float) {
                if (std.math.isInf(a) and std.math.isInf(b)) {
                    break :blk (a > 0) == (b > 0);
                }
                if (std.math.isNan(a) or std.math.isNan(b)) {
                    break :blk false;
                }
                break :blk @abs(a - b) < 0.0001;
            }
            if (a_info == .array) {
                break :blk std.mem.eql(@TypeOf(a[0]), &a, &b);
            }
            if (a_info == .pointer and a_info.pointer.size == .slice) {
                break :blk std.mem.eql(a_info.pointer.child, a, b);
            }
            if (a_info == .@"struct" and @hasDecl(A, "eql")) {
                const EqlFn = @TypeOf(A.eql);
                const eql_params = @typeInfo(EqlFn).@"fn".params;
                if (eql_params.len >= 2) {
                    const second_param_type = eql_params[1].type orelse break :blk a.eql(b);
                    if (@typeInfo(second_param_type) == .pointer) {
                        break :blk a.eql(&b);
                    }
                }
                break :blk a.eql(b);
            }
            if (a_info == .@"struct" and @hasField(A, "items") and @hasField(A, "capacity")) {
                break :blk equalArrayList(a, b);
            }
            if (a_info == .@"struct" and a_info.@"struct".is_tuple) {
                break :blk equalTuples(a, b);
            }
            if (a_info == .@"struct") {
                break :blk runtime.pyAnyEql(a, b);
            }
            if (a_info == .@"union") {
                break :blk runtime.pyAnyEql(a, b);
            }
            if (comptime (a_info == .pointer and a_info.pointer.size == .one)) {
                const child = a_info.pointer.child;
                const child_info = @typeInfo(child);
                if (comptime (child_info == .@"struct" and @hasField(child, "__base_value__"))) {
                    const BaseType = @TypeOf(a.*.__base_value__);
                    if (comptime (BaseType == f64 or BaseType == f32)) {
                        break :blk @abs(@as(f64, a.*.__base_value__) - @as(f64, b.*.__base_value__)) < 0.0001;
                    }
                    if (comptime (BaseType == i64)) {
                        break :blk a.*.__base_value__ == b.*.__base_value__;
                    }
                }
            }
            break :blk a == b;
        }

        // ArrayList comparison - different ArrayList types
        if (a_info == .@"struct" and b_info == .@"struct") {
            if (@hasField(A, "items") and @hasField(A, "capacity") and
                @hasField(B, "items") and @hasField(B, "capacity"))
            {
                break :blk equalArrayList(a, b);
            }
        }

        // Tuple comparison
        if (a_info == .@"struct" and b_info == .@"struct") {
            if (a_info.@"struct".is_tuple and b_info.@"struct".is_tuple) {
                break :blk equalTuples(a, b);
            }
        }

        // PyValue union vs Zig tuple/array
        if (a_info == .@"union" and @hasField(A, "list") and @hasField(A, "tuple") and @hasField(A, "int")) {
            break :blk equalPyValueWith(a, b);
        }
        if (b_info == .@"union" and @hasField(B, "list") and @hasField(B, "tuple") and @hasField(B, "int")) {
            break :blk equalPyValueWith(b, a);
        }

        // ArrayList vs array comparison
        if (a_info == .@"struct" and @hasField(A, "items") and @hasField(A, "capacity") and b_info == .array) {
            if (a.items.len != b.len) break :blk false;
            for (a.items, 0..) |a_elem, i| {
                if (!elemEql(a_elem, b[i])) break :blk false;
            }
            break :blk true;
        }
        if (b_info == .@"struct" and @hasField(B, "items") and @hasField(B, "capacity") and a_info == .array) {
            if (b.items.len != a.len) break :blk false;
            for (b.items, 0..) |b_elem, i| {
                if (!elemEql(b_elem, a[i])) break :blk false;
            }
            break :blk true;
        }

        // ArrayList vs Zig tuple
        if (a_info == .@"struct" and @hasField(A, "items") and @hasField(A, "capacity") and b_info == .@"struct" and b_info.@"struct".is_tuple) {
            const b_fields = b_info.@"struct".fields;
            if (a.items.len != b_fields.len) break :blk false;
            inline for (b_fields, 0..) |field, i| {
                const b_elem = @field(b, field.name);
                if (!elemEql(a.items[i], b_elem)) break :blk false;
            }
            break :blk true;
        }
        if (b_info == .@"struct" and @hasField(B, "items") and @hasField(B, "capacity") and a_info == .@"struct" and a_info.@"struct".is_tuple) {
            const a_fields = a_info.@"struct".fields;
            if (b.items.len != a_fields.len) break :blk false;
            inline for (a_fields, 0..) |field, i| {
                const a_elem = @field(a, field.name);
                if (!elemEql(b.items[i], a_elem)) break :blk false;
            }
            break :blk true;
        }

        // Struct with eql method
        if (a_info == .@"struct" and @hasDecl(A, "eql")) {
            const eql_info = @typeInfo(@TypeOf(A.eql));
            if (eql_info == .@"fn" and eql_info.@"fn".params.len >= 2) {
                const expected_param = eql_info.@"fn".params[1].type;
                if (expected_param) |param_type| {
                    if (param_type == B or param_type == *const B) {
                        break :blk a.eql(b);
                    }
                } else {
                    break :blk a.eql(b);
                }
            }
        }
        if (b_info == .@"struct" and @hasDecl(B, "eql")) {
            const eql_info = @typeInfo(@TypeOf(B.eql));
            if (eql_info == .@"fn" and eql_info.@"fn".params.len >= 2) {
                const expected_param = eql_info.@"fn".params[1].type;
                if (expected_param) |param_type| {
                    if (param_type == A or param_type == *const A) {
                        break :blk b.eql(a);
                    }
                } else {
                    break :blk b.eql(a);
                }
            }
        }

        // Python class struct with __eq__ method
        if (a_info == .@"struct" and @hasDecl(A, "__eq__")) {
            const eq_info = @typeInfo(@TypeOf(A.__eq__));
            if (eq_info == .@"fn") {
                const params = eq_info.@"fn".params;
                const result = if (params.len == 3)
                    a.__eq__(allocator_helper.fast_allocator, b)
                else
                    a.__eq__(b);
                const ResultType = @TypeOf(result);
                if (@typeInfo(ResultType) == .error_union) {
                    const eq_result = result catch break :blk false;
                    if (@TypeOf(eq_result) == bool) {
                        break :blk eq_result;
                    }
                    break :blk false;
                } else if (ResultType == bool) {
                    break :blk result;
                }
            }
            break :blk false;
        }
        if (b_info == .@"struct" and @hasDecl(B, "__eq__")) {
            const eq_info = @typeInfo(@TypeOf(B.__eq__));
            if (eq_info == .@"fn") {
                const params = eq_info.@"fn".params;
                const result = if (params.len == 3)
                    b.__eq__(allocator_helper.fast_allocator, a)
                else
                    b.__eq__(a);
                const ResultType = @TypeOf(result);
                if (@typeInfo(ResultType) == .error_union) {
                    const eq_result = result catch break :blk false;
                    if (@TypeOf(eq_result) == bool) {
                        break :blk eq_result;
                    }
                    break :blk false;
                } else if (ResultType == bool) {
                    break :blk result;
                }
            }
            break :blk false;
        }

        // Integer comparisons
        if ((a_info == .int or a_info == .comptime_int) and (b_info == .int or b_info == .comptime_int)) {
            break :blk a == b;
        }

        // BigInt vs int comparisons
        if (a_info == .@"struct" and @hasDecl(A, "toInt128") and (b_info == .int or b_info == .comptime_int)) {
            if (a.toInt128()) |a_val| {
                break :blk a_val == @as(i128, b);
            }
            break :blk false;
        }
        if (b_info == .@"struct" and @hasDecl(B, "toInt128") and (a_info == .int or a_info == .comptime_int)) {
            if (b.toInt128()) |b_val| {
                break :blk @as(i128, a) == b_val;
            }
            break :blk false;
        }

        // Float comparisons
        if ((a_info == .float or a_info == .comptime_float) and (b_info == .float or b_info == .comptime_float)) {
            break :blk @abs(@as(f64, a) - @as(f64, b)) < 0.0001;
        }

        // Float to int comparisons
        if ((a_info == .float or a_info == .comptime_float) and (b_info == .int or b_info == .comptime_int)) {
            break :blk @abs(@as(f64, a) - @as(f64, @floatFromInt(b))) < 0.0001;
        }
        if ((a_info == .int or a_info == .comptime_int) and (b_info == .float or b_info == .comptime_float)) {
            break :blk @abs(@as(f64, @floatFromInt(a)) - @as(f64, b)) < 0.0001;
        }

        // Float subclass comparisons
        if (a_info == .@"struct" and @hasField(A, "__base_value__") and (b_info == .float or b_info == .comptime_float)) {
            const BaseType = @TypeOf(a.__base_value__);
            if (BaseType == f64 or BaseType == f32) {
                break :blk @abs(@as(f64, a.__base_value__) - @as(f64, b)) < 0.0001;
            }
        }
        if ((a_info == .float or a_info == .comptime_float) and b_info == .@"struct" and @hasField(B, "__base_value__")) {
            const BaseType = @TypeOf(b.__base_value__);
            if (BaseType == f64 or BaseType == f32) {
                break :blk @abs(@as(f64, a) - @as(f64, b.__base_value__)) < 0.0001;
            }
        }

        // Pointer to float subclass
        if (a_info == .pointer and a_info.pointer.size == .one) {
            const child = a_info.pointer.child;
            const child_info = @typeInfo(child);
            if (child_info == .@"struct" and @hasField(child, "__base_value__")) {
                const BaseType = @TypeOf(a.*.__base_value__);
                if ((BaseType == f64 or BaseType == f32) and (b_info == .float or b_info == .comptime_float)) {
                    break :blk @abs(@as(f64, a.*.__base_value__) - @as(f64, b)) < 0.0001;
                }
            }
        }
        if (b_info == .pointer and b_info.pointer.size == .one) {
            const child = b_info.pointer.child;
            const child_info = @typeInfo(child);
            if (child_info == .@"struct" and @hasField(child, "__base_value__")) {
                const BaseType = @TypeOf(b.*.__base_value__);
                if ((BaseType == f64 or BaseType == f32) and (a_info == .float or a_info == .comptime_float)) {
                    break :blk @abs(@as(f64, a) - @as(f64, b.*.__base_value__)) < 0.0001;
                }
            }
        }

        // Two pointers to struct
        if (comptime (a_info == .pointer and a_info.pointer.size == .one and
            b_info == .pointer and b_info.pointer.size == .one))
        {
            const a_child = a_info.pointer.child;
            const b_child = b_info.pointer.child;
            const a_child_info = @typeInfo(a_child);
            const b_child_info = @typeInfo(b_child);
            if (comptime (a_child_info == .@"struct" and @hasField(a_child, "__base_value__") and
                b_child_info == .@"struct" and @hasField(b_child, "__base_value__")))
            {
                const ABaseType = @TypeOf(a.*.__base_value__);
                const BBaseType = @TypeOf(b.*.__base_value__);
                if (comptime ((ABaseType == f64 or ABaseType == f32) and (BBaseType == f64 or BBaseType == f32))) {
                    break :blk @abs(@as(f64, a.*.__base_value__) - @as(f64, b.*.__base_value__)) < 0.0001;
                }
            }
        }

        // Bool comparisons
        if (a_info == .bool and b_info == .bool) {
            break :blk a == b;
        }

        // Pointer handling (slices and string literals)
        if (a_info == .pointer) {
            const ptr = a_info.pointer;
            if (ptr.size == .slice and ptr.child == u8) {
                if (b_info == .pointer) {
                    if (b_info.pointer.size == .slice and b_info.pointer.child == u8) {
                        break :blk std.mem.eql(u8, a, b);
                    }
                    if (b_info.pointer.size == .one) {
                        const child_info = @typeInfo(b_info.pointer.child);
                        if (child_info == .array and child_info.array.child == u8) {
                            const b_slice: []const u8 = b;
                            break :blk std.mem.eql(u8, a, b_slice);
                        }
                    }
                }
                break :blk false;
            }
            if (ptr.size == .slice) {
                if (b_info == .pointer and b_info.pointer.size == .slice) {
                    break :blk std.mem.eql(u8, a, b);
                }
                break :blk false;
            }
            // Check if a is a PyObject*
            if (ptr.size == .one and ptr.child == runtime.PyObject) {
                const a_type = runtime.getTypeId(a);
                if (b_info == .int or b_info == .comptime_int) {
                    if (a_type == .int) {
                        const pyint = runtime.PyInt.getValue(a);
                        break :blk pyint == @as(i64, b);
                    } else if (a_type == .bool) {
                        const pybool = runtime.PyBool.getValue(a);
                        break :blk @as(i64, if (pybool) 1 else 0) == @as(i64, b);
                    }
                    break :blk false;
                } else if (b_info == .bool) {
                    if (a_type == .bool) {
                        const pybool = runtime.PyBool.getValue(a);
                        break :blk pybool == b;
                    }
                    break :blk false;
                } else if (b_info == .pointer and b_info.pointer.size == .slice) {
                    if (a_type == .string) {
                        const pystr = runtime.PyString.getValue(a);
                        break :blk std.mem.eql(u8, pystr, b);
                    }
                    break :blk false;
                } else if (b_info == .pointer and b_info.pointer.size == .one) {
                    const b_child_info = @typeInfo(b_info.pointer.child);
                    if (b_child_info == .array and b_child_info.array.child == u8) {
                        if (a_type == .string) {
                            const pystr = runtime.PyString.getValue(a);
                            const b_slice: []const u8 = b;
                            break :blk std.mem.eql(u8, pystr, b_slice);
                        }
                    }
                    break :blk false;
                } else if (b_info == .array) {
                    const arr = b_info.array;
                    if (arr.child == u8 and a_type == .string) {
                        const pystr = runtime.PyString.getValue(a);
                        break :blk std.mem.eql(u8, pystr, &b);
                    }
                    if (a_type == .list) {
                        const list_len = runtime.PyList.len(a);
                        if (list_len != b.len) break :blk false;
                        for (0..list_len) |i| {
                            const elem = runtime.PyList.getItem(a, i) catch break :blk false;
                            const ElemType = @TypeOf(b[0]);
                            if (@typeInfo(ElemType) == .pointer and @typeInfo(ElemType).pointer.child == u8) {
                                const elem_type = runtime.getTypeId(elem);
                                if (elem_type == .string) {
                                    const elem_str = runtime.PyString.getValue(elem);
                                    if (!std.mem.eql(u8, elem_str, b[i])) break :blk false;
                                } else {
                                    break :blk false;
                                }
                            } else {
                                break :blk false;
                            }
                        }
                        break :blk true;
                    }
                    break :blk false;
                }
            }
        }

        // Check if b is a PyObject* and a is an integer
        if (b_info == .pointer and b_info.pointer.size == .one) {
            const child = b_info.pointer.child;
            const child_info = @typeInfo(child);
            if (child_info == .@"struct" and @hasField(child, "ob_refcnt") and @hasField(child, "ob_type")) {
                if (a_info == .int or a_info == .comptime_int) {
                    const b_type = runtime.getTypeId(b);
                    if (b_type == .int) {
                        const pyint = runtime.PyInt.getValue(b);
                        break :blk @as(i64, @intCast(a)) == pyint;
                    } else if (b_type == .bool) {
                        const pybool = runtime.PyBool.getValue(b);
                        break :blk @as(i64, @intCast(a)) == @as(i64, if (pybool) 1 else 0);
                    }
                    break :blk false;
                }
            }
        }

        // Try equalValues for struct-to-struct comparison
        if (a_info == .@"struct" and b_info == .@"struct") {
            break :blk equalValues(a, b);
        }

        // Incompatible types - always false
        break :blk false;
    };

    if (!equal) {
        const a_is_string = comptime isStringType(A);
        const b_is_string = comptime isStringType(B);
        if (a_is_string and b_is_string) {
            std.debug.print("AssertionError: '{s}' != '{s}'\n", .{ a, b });
        } else if (a_is_string) {
            std.debug.print("AssertionError: '{s}' != {any}\n", .{ a, b });
        } else if (b_is_string) {
            std.debug.print("AssertionError: {any} != '{s}'\n", .{ a, b });
        } else {
            std.debug.print("AssertionError: {any} != {any}\n", .{ a, b });
        }
        if (runner.global_result) |result| {
            result.addFail("assertEqual failed") catch {};
        }
        return error.AssertionFailed;
    } else {
        if (runner.global_result) |result| {
            result.addPass();
        }
    }
}
