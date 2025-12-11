//! XML Errors - error types for XML parsing and processing
//!
//! This module defines error types used throughout the XML modules.

/// XML-related errors
pub const XMLError = error{
    ParseError,
    MalformedXML,
    InvalidCharacter,
    UndefinedEntity,
    DuplicateAttribute,
};
