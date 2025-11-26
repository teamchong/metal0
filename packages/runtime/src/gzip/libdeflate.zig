// libdeflate C library bindings
// Provides direct access to libdeflate compression functions

pub const c = @cImport({
    @cInclude("libdeflate.h");
});
