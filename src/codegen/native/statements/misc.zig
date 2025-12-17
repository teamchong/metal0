/// Miscellaneous statement code generation - Re-exports from submodules
/// Split into: return, imports, global, delete, assert, with, raise

// Re-export print statement generation
pub const genPrint = @import("print.zig").genPrint;

// Re-export from submodules
pub const genReturn = @import("misc/return_stmt.zig").genReturn;
pub const genImport = @import("misc/imports.zig").genImport;
pub const genImportFrom = @import("misc/imports.zig").genImportFrom;
pub const genGlobal = @import("misc/global_stmt.zig").genGlobal;
pub const genDel = @import("misc/delete.zig").genDel;
pub const genAssert = @import("misc/assert_stmt.zig").genAssert;
pub const genWith = @import("misc/with.zig").genWith;
pub const genRaise = @import("misc/raise.zig").genRaise;
