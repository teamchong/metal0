//! CPython source: Lib/socket.py
//!
//! Provides access to the BSD socket interface.
//!
//! Mirrors: CPython Lib/socket.py
//!
//! This module has been split into a modular directory structure:
//! - socket/constants.zig - Socket constants and enums
//! - socket/address.zig - Address handling and parsing
//! - socket/socket_class.zig - Socket class implementation
//! - socket/utils.zig - Utility functions

// Re-export all constants
const constants = @import("socket/constants.zig");
pub const AF_UNSPEC = constants.AF_UNSPEC;
pub const AF_UNIX = constants.AF_UNIX;
pub const AF_INET = constants.AF_INET;
pub const AF_INET6 = constants.AF_INET6;
pub const AF_LOCAL = constants.AF_LOCAL;
pub const SOCK_STREAM = constants.SOCK_STREAM;
pub const SOCK_DGRAM = constants.SOCK_DGRAM;
pub const SOCK_RAW = constants.SOCK_RAW;
pub const SOCK_SEQPACKET = constants.SOCK_SEQPACKET;
pub const IPPROTO_IP = constants.IPPROTO_IP;
pub const IPPROTO_ICMP = constants.IPPROTO_ICMP;
pub const IPPROTO_TCP = constants.IPPROTO_TCP;
pub const IPPROTO_UDP = constants.IPPROTO_UDP;
pub const IPPROTO_IPV6 = constants.IPPROTO_IPV6;
pub const SOL_SOCKET = constants.SOL_SOCKET;
pub const SO_REUSEADDR = constants.SO_REUSEADDR;
pub const SO_KEEPALIVE = constants.SO_KEEPALIVE;
pub const SO_BROADCAST = constants.SO_BROADCAST;
pub const SO_LINGER = constants.SO_LINGER;
pub const SO_RCVBUF = constants.SO_RCVBUF;
pub const SO_SNDBUF = constants.SO_SNDBUF;
pub const SO_RCVTIMEO = constants.SO_RCVTIMEO;
pub const SO_SNDTIMEO = constants.SO_SNDTIMEO;
pub const IPPROTO_TCP_CONST = constants.IPPROTO_TCP_CONST;
pub const TCP_NODELAY = constants.TCP_NODELAY;
pub const INADDR_ANY = constants.INADDR_ANY;
pub const INADDR_BROADCAST = constants.INADDR_BROADCAST;
pub const INADDR_LOOPBACK = constants.INADDR_LOOPBACK;
pub const SOMAXCONN = constants.SOMAXCONN;
pub const TIMEOUT_NONE = constants.TIMEOUT_NONE;
pub const TIMEOUT_DEFAULT = constants.TIMEOUT_DEFAULT;
pub const SocketError = constants.SocketError;
pub const ShutdownHow = constants.ShutdownHow;

// Re-export address types and functions
pub const address = @import("socket/address.zig");
pub const Address = address.Address;
pub const inet_aton = address.inet_aton;
pub const inet_ntoa = address.inet_ntoa;
pub const htons = address.htons;
pub const ntohs = address.ntohs;
pub const htonl = address.htonl;
pub const ntohl = address.ntohl;

// Re-export socket class
pub const socket_class = @import("socket/socket_class.zig");
pub const Socket = socket_class.Socket;
pub const hasData = socket_class.hasData;
pub const setInheritable = socket_class.setInheritable;

// Re-export utility functions
pub const utils = @import("socket/utils.zig");
pub const socket = utils.socket;
pub const socketpair = utils.socketpair;
pub const createConnection = utils.createConnection;
pub const gethostname = utils.gethostname;
pub const getfqdn = utils.getfqdn;
pub const getaddrinfo = utils.getaddrinfo;

// Re-export tests from submodules
comptime {
    _ = constants;
    _ = address;
    _ = socket_class;
    _ = utils;
}

// ============================================================================
// Module-level Tests
// ============================================================================

const std = @import("std");

test "constants" {
    try std.testing.expectEqual(@as(i32, 2), AF_INET);
    try std.testing.expectEqual(@as(i32, 1), SOCK_STREAM);
    try std.testing.expectEqual(@as(i32, 6), IPPROTO_TCP);
}
