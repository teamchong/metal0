//! Tkinter error types, constants, and option values
//!
//! Defines the foundational types used throughout the tkinter module:
//! - Error types for Tk operations
//! - Constants for anchors, fill, relief, state, etc.
//! - OptionValue union for widget configuration

// ============================================================================
// Error Types
// ============================================================================

pub const TkError = error{
    TclError,
    TkNotAvailable,
    WidgetDestroyed,
    InvalidOption,
    OutOfMemory,
};

// ============================================================================
// Constants
// ============================================================================

// Boolean constants
pub const YES = true;
pub const NO = false;
pub const TRUE = true;
pub const FALSE = false;
pub const ON = true;
pub const OFF = false;

// Anchor positions
pub const N = "n";
pub const NE = "ne";
pub const E = "e";
pub const SE = "se";
pub const S = "s";
pub const SW = "sw";
pub const W = "w";
pub const NW = "nw";
pub const CENTER = "center";

// Fill options
pub const NONE = "none";
pub const X = "x";
pub const Y = "y";
pub const BOTH = "both";

// Side options
pub const LEFT = "left";
pub const TOP = "top";
pub const RIGHT = "right";
pub const BOTTOM = "bottom";

// Relief styles
pub const RAISED = "raised";
pub const SUNKEN = "sunken";
pub const FLAT = "flat";
pub const RIDGE = "ridge";
pub const GROOVE = "groove";
pub const SOLID = "solid";

// State values
pub const NORMAL = "normal";
pub const DISABLED = "disabled";
pub const ACTIVE = "active";
pub const HIDDEN = "hidden";

// Selection modes
pub const SINGLE = "single";
pub const BROWSE = "browse";
pub const MULTIPLE = "multiple";
pub const EXTENDED = "extended";

// Wrap modes
pub const CHAR = "char";
pub const WORD = "word";

// Cursor types
pub const INSERT = "insert";
pub const CURRENT = "current";
pub const END = "end";
pub const SEL = "sel";
pub const SEL_FIRST = "sel.first";
pub const SEL_LAST = "sel.last";

// ============================================================================
// Option Value Type
// ============================================================================

/// Widget option value (can be string, int, bool, or callback)
pub const OptionValue = union(enum) {
    string: []const u8,
    int: i32,
    boolean: bool,
    callback: ?*const fn () void,
};
