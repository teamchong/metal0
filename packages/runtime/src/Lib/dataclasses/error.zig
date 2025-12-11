//! Dataclass error types
//!
//! Provides error types used when operations violate dataclass constraints.

/// Error thrown when attempting to mutate a frozen dataclass instance
pub const FrozenInstanceError = error{
    FrozenInstanceError,
};
