/// BLAKE2 module wrapper
/// Ported from CPython Modules/_blake2/blake2module.c
const std = @import("std");
const blake2b_impl = @import("blake2b_impl.zig");
const blake2s_impl = @import("blake2s_impl.zig");

pub const blake2b = blake2b_impl.Blake2b;
pub const blake2s = blake2s_impl.Blake2s;

// DCE-friendly: Re-exports for hashlib integration
