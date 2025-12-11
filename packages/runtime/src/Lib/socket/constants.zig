//! Socket constants and enums
//!
//! Provides all socket-related constants including address families,
//! socket types, protocols, options, and special values.

const std = @import("std");
const posix = std.posix;

// ============================================================================
// Address Families
// ============================================================================

pub const AF_UNSPEC = posix.AF.UNSPEC;
pub const AF_UNIX = posix.AF.UNIX;
pub const AF_INET = posix.AF.INET;
pub const AF_INET6 = posix.AF.INET6;

// Platform-specific address families
pub const AF_LOCAL = AF_UNIX;

// ============================================================================
// Socket Types
// ============================================================================

pub const SOCK_STREAM = posix.SOCK.STREAM;
pub const SOCK_DGRAM = posix.SOCK.DGRAM;
pub const SOCK_RAW = posix.SOCK.RAW;
pub const SOCK_SEQPACKET = posix.SOCK.SEQPACKET;

// ============================================================================
// Protocol Numbers
// ============================================================================

pub const IPPROTO_IP = 0;
pub const IPPROTO_ICMP = 1;
pub const IPPROTO_TCP = 6;
pub const IPPROTO_UDP = 17;
pub const IPPROTO_IPV6 = 41;

// ============================================================================
// Socket Options
// ============================================================================

pub const SOL_SOCKET = posix.SOL.SOCKET;

pub const SO_REUSEADDR = posix.SO.REUSEADDR;
pub const SO_KEEPALIVE = posix.SO.KEEPALIVE;
pub const SO_BROADCAST = posix.SO.BROADCAST;
pub const SO_LINGER = posix.SO.LINGER;
pub const SO_RCVBUF = posix.SO.RCVBUF;
pub const SO_SNDBUF = posix.SO.SNDBUF;
pub const SO_RCVTIMEO = posix.SO.RCVTIMEO;
pub const SO_SNDTIMEO = posix.SO.SNDTIMEO;

// TCP options
pub const IPPROTO_TCP_CONST = 6;
pub const TCP_NODELAY = 1;

// ============================================================================
// Special Constants
// ============================================================================

pub const INADDR_ANY: u32 = 0;
pub const INADDR_BROADCAST: u32 = 0xFFFFFFFF;
pub const INADDR_LOOPBACK: u32 = 0x7F000001;

/// Default backlog for listen()
pub const SOMAXCONN = 128;

/// Special timeout values
pub const TIMEOUT_NONE: ?f64 = null;
pub const TIMEOUT_DEFAULT: f64 = -1;

// ============================================================================
// Error codes
// ============================================================================

pub const SocketError = error{
    AddressInUse,
    ConnectionRefused,
    ConnectionReset,
    NetworkUnreachable,
    HostUnreachable,
    TimedOut,
    WouldBlock,
    NotConnected,
    InvalidArgument,
    PermissionDenied,
    SocketNotBound,
    AlreadyConnected,
    OperationNotSupported,
};

// ============================================================================
// Enums
// ============================================================================

/// Shutdown direction
pub const ShutdownHow = enum(i32) {
    SHUT_RD = 0,
    SHUT_WR = 1,
    SHUT_RDWR = 2,
};
