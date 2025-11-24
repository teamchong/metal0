/// C Interop module - exports all C library wrappers
/// This allows @import("./c_interop/c_interop.zig").numpy syntax

pub const numpy = @import("numpy.zig");
pub const sqlite3 = @import("sqlite3.zig");
pub const zlib = @import("zlib.zig");
pub const ssl = @import("ssl.zig");
