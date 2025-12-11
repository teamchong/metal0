//! Pickle protocol version detection.
//!
//! Detects the protocol version of pickle data.
//! Mirrors: CPython Lib/pickletools.py - getProtocol function

const types = @import("types.zig");

pub const Opcode = types.Opcode;

/// Get the protocol version of a pickle
pub fn getProtocol(pickle: []const u8) u8 {
    if (pickle.len >= 2 and pickle[0] == @intFromEnum(Opcode.PROTO)) {
        return pickle[1];
    }
    // Default to protocol 0 for old pickles
    return 0;
}
