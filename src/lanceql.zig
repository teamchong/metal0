//! LanceQL - A Zig implementation of the Lance columnar file format reader.
//!
//! This library provides read-only access to Lance files, supporting both
//! native execution and WebAssembly (browser) targets.
//!
//! ## Example
//! ```zig
//! const lanceql = @import("lanceql");
//!
//! pub fn main() !void {
//!     var file = try lanceql.LanceFile.open("data.lance");
//!     defer file.close();
//!
//!     const footer = file.footer();
//!     std.debug.print("Columns: {}\n", .{footer.num_columns});
//! }
//! ```

const std = @import("std");

pub const format = @import("lanceql.format");
pub const io = @import("lanceql.io");
pub const proto = @import("lanceql.proto");
pub const encoding = @import("lanceql.encoding");
pub const table = @import("lanceql.table");
pub const logic_table = @import("lanceql.logic_table");

// Re-export commonly used types
pub const Footer = format.Footer;
pub const Version = format.Version;
pub const Reader = io.Reader;
pub const Table = table.Table;
pub const LanceFile = format.LanceFile;

/// Magic bytes at the end of every Lance file
pub const LANCE_MAGIC = "LANC";

/// Size of the Lance file footer in bytes
pub const FOOTER_SIZE: usize = 40;

test {
    std.testing.refAllDecls(@This());
}
