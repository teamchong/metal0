//! Error types for IP address handling
//!
//! CPython source: Lib/ipaddress.py

/// Error types for IP address operations
pub const AddressValueError = error{
    /// Invalid address format
    InvalidAddress,
    /// Invalid network format
    InvalidNetwork,
    /// Invalid prefix length
    InvalidPrefixLen,
    /// Address is not in network
    AddressNotInNetwork,
    /// Host bits set in network address
    HostBitsSet,
};
