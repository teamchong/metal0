//! Constants for IP address handling
//!
//! CPython source: Lib/ipaddress.py

/// IPv4 constants
pub const IPV4 = struct {
    pub const LENGTH = 32;
    pub const MAX_PREFIXLEN = 32;
    pub const ALL_ONES: u32 = 0xFFFFFFFF;
};

/// IPv6 constants
pub const IPV6 = struct {
    pub const LENGTH = 128;
    pub const MAX_PREFIXLEN = 128;
    pub const ALL_ONES: u128 = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF;
};
