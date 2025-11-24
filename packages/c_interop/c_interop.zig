/// C Interop module - exports all C library wrappers
/// This allows @import("c_interop").numpy syntax

pub const numpy = @import("src/numpy.zig");
pub const sqlite3 = @import("src/sqlite3.zig");
pub const zlib = @import("src/zlib.zig");
pub const ssl = @import("src/ssl.zig");
