/// Helper functions for creating Python objects from bytecode constants
const std = @import("std");
const runtime = @import("../../runtime.zig");
const PyObject = runtime.PyObject;
const BigInt = @import("bigint").BigInt;

/// PyBigInt helper for creating BigInt-backed PyObjects
pub const PyBigInt = struct {
    /// Create a PyBigIntObject from a string (handles base prefixes)
    pub fn create(allocator: std.mem.Allocator, str: []const u8) !*PyObject {
        // Detect base from prefix
        var base: u8 = 10;
        var num_str = str;
        if (str.len > 2 and str[0] == '0') {
            const prefix = str[1];
            if (prefix == 'b' or prefix == 'B') {
                base = 2;
                num_str = str[2..];
            } else if (prefix == 'o' or prefix == 'O') {
                base = 8;
                num_str = str[2..];
            } else if (prefix == 'x' or prefix == 'X') {
                base = 16;
                num_str = str[2..];
            }
        }
        const obj = try allocator.create(runtime.PyBigIntObject);
        obj.* = .{
            .ob_base = .{
                .ob_base = .{
                    .ob_refcnt = 1,
                    .ob_type = &runtime.cpython.PyBigInt_Type,
                },
                .ob_size = 1,
            },
            .value = try BigInt.fromString(allocator, num_str, base),
        };
        return @ptrCast(obj);
    }

    /// Create a PyBigIntObject from a BigInt value
    pub fn createFromBigInt(allocator: std.mem.Allocator, value: BigInt) !*PyObject {
        const obj = try allocator.create(runtime.PyBigIntObject);
        obj.* = .{
            .ob_base = .{
                .ob_base = .{
                    .ob_refcnt = 1,
                    .ob_type = &runtime.cpython.PyBigInt_Type,
                },
                .ob_size = 1,
            },
            .value = value,
        };
        return @ptrCast(obj);
    }

    /// Get the BigInt value from a PyBigIntObject
    pub fn getValue(obj: *PyObject) *BigInt {
        std.debug.assert(runtime.PyBigInt_Check(obj));
        const bigint_obj: *runtime.PyBigIntObject = @ptrCast(@alignCast(obj));
        return &bigint_obj.value;
    }
};

/// Create a PyBytes object from data
pub fn createPyBytes(allocator: std.mem.Allocator, data: []const u8) !*PyObject {
    // Allocate PyBytesObject with extra space for the data
    const total_size = @sizeOf(runtime.PyBytesObject) - 1 + data.len + 1; // -1 for ob_sval[1], +1 for null terminator
    const mem = try allocator.alloc(u8, total_size);
    const bytes_obj: *runtime.PyBytesObject = @ptrCast(@alignCast(mem.ptr));
    bytes_obj.* = .{
        .ob_base = .{
            .ob_base = .{
                .ob_refcnt = 1,
                .ob_type = &runtime.cpython.PyBytes_Type,
            },
            .ob_size = @intCast(data.len),
        },
        .ob_shash = -1,
        .ob_sval = undefined,
    };
    // Copy data into the trailing buffer
    const dest = mem[@offsetOf(runtime.PyBytesObject, "ob_sval")..];
    @memcpy(dest[0..data.len], data);
    dest[data.len] = 0; // Null terminator
    return @ptrCast(bytes_obj);
}
