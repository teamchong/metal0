const std = @import("std");
const runtime = @import("./runtime.zig");
const hashmap_helper = @import("./utils/hashmap_helper.zig");
const allocator_helper = @import("./utils/allocator_helper.zig");

const __name__ = "__main__";
const __file__: []const u8 = "benchmarks/vector_ops.py";

// metal0 metadata for runtime eval subprocess
pub const __metal0_source_dir: []const u8 = "benchmarks";


// Module-level allocator for f-strings and dynamic allocations
var __gpa = std.heap.GeneralPurposeAllocator(.{ .safety = true }){};
var __global_allocator: std.mem.Allocator = __gpa.allocator();

pub const vector_ops = struct {
    const VectorOps = struct {
        // Dynamic attributes dictionary
        __dict__: hashmap_helper.StringHashMap(runtime.PyValue),

        pub fn init(allocator: std.mem.Allocator) @This() {
            return @This(){
                .__dict__ = hashmap_helper.StringHashMap(runtime.PyValue).init(allocator),
            };
        }

        pub fn dot_product(_: *const @This(), a: anytype, b: anytype) f64 {
            _ = "\"\"Compute dot product of two vectors.\"\"";
            const result: f64 = 0.0;
            {
                var i: isize = 0;
                while (i < @as(i64, @intCast(len_0: { const __tmp = a; break :len_0 if (@typeInfo(@TypeOf(__tmp)) == .@"struct" and @hasField(@TypeOf(__tmp), "items")) __tmp.items.len else runtime.pyLen(__tmp); }))) {
                    result = (result + blk: { const _lhs = a[i]; const _rhs = b[i]; break :blk if (@TypeOf(_lhs) == []const u8) runtime.strRepeat(__global_allocator, _lhs, @as(usize, @intCast(_rhs))) else _lhs * _rhs; });
                    i += 1;
                }
            }
            return result;
        }

        pub fn sum_squares(_: *const @This(), a: anytype) f64 {
            _ = "\"\"Compute sum of squares.\"\"";
            const result: f64 = 0.0;
            {
                var i: isize = 0;
                while (i < @as(i64, @intCast(len_1: { const __tmp = a; break :len_1 if (@typeInfo(@TypeOf(__tmp)) == .@"struct" and @hasField(@TypeOf(__tmp), "items")) __tmp.items.len else runtime.pyLen(__tmp); }))) {
                    result = (result + blk: { const _lhs = a[i]; const _rhs = a[i]; break :blk if (@TypeOf(_lhs) == []const u8) runtime.strRepeat(__global_allocator, _lhs, @as(usize, @intCast(_rhs))) else _lhs * _rhs; });
                    i += 1;
                }
            }
            return result;
        }

        pub fn sum_values(_: *const @This(), a: anytype) f64 {
            _ = "\"\"Sum all values in array.\"\"";
            const result: f64 = 0.0;
            {
                var i: isize = 0;
                while (i < @as(i64, @intCast(len_2: { const __tmp = a; break :len_2 if (@typeInfo(@TypeOf(__tmp)) == .@"struct" and @hasField(@TypeOf(__tmp), "items")) __tmp.items.len else runtime.pyLen(__tmp); }))) {
                    result = (result + (a[i]));
                    i += 1;
                }
            }
            return result;
        }
    };

};
