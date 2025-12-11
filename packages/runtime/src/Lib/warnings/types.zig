//! Core types for warnings module
//!
//! Defines warning categories, filter actions, and related data structures.

const std = @import("std");

// ============================================================================
// Call Stack Tracking Types
// ============================================================================

/// Frame info for stack tracking
pub const FrameInfo = struct {
    filename: []const u8,
    lineno: usize,
    function: []const u8,
};

// ============================================================================
// Warning Categories
// ============================================================================

/// Warning category hierarchy
pub const WarningCategory = enum {
    Warning,
    UserWarning,
    DeprecationWarning,
    PendingDeprecationWarning,
    SyntaxWarning,
    RuntimeWarning,
    FutureWarning,
    ImportWarning,
    UnicodeWarning,
    BytesWarning,
    EncodingWarning,
    ResourceWarning,

    pub fn name(self: WarningCategory) []const u8 {
        return switch (self) {
            .Warning => "Warning",
            .UserWarning => "UserWarning",
            .DeprecationWarning => "DeprecationWarning",
            .PendingDeprecationWarning => "PendingDeprecationWarning",
            .SyntaxWarning => "SyntaxWarning",
            .RuntimeWarning => "RuntimeWarning",
            .FutureWarning => "FutureWarning",
            .ImportWarning => "ImportWarning",
            .UnicodeWarning => "UnicodeWarning",
            .BytesWarning => "BytesWarning",
            .EncodingWarning => "EncodingWarning",
            .ResourceWarning => "ResourceWarning",
        };
    }

    /// Check if this category is a subclass of another
    pub fn isSubclassOf(self: WarningCategory, other: WarningCategory) bool {
        if (self == other) return true;
        // All warnings are subclass of Warning
        if (other == .Warning) return true;
        return false;
    }
};

// ============================================================================
// Filter Actions
// ============================================================================

/// Warning filter actions
pub const FilterAction = enum {
    default, // Print first occurrence
    @"error", // Raise as exception
    ignore, // Never print
    always, // Always print
    module, // Print first occurrence per module
    once, // Print first occurrence anywhere

    pub fn fromString(s: []const u8) ?FilterAction {
        if (std.mem.eql(u8, s, "default")) return .default;
        if (std.mem.eql(u8, s, "error")) return .@"error";
        if (std.mem.eql(u8, s, "ignore")) return .ignore;
        if (std.mem.eql(u8, s, "always")) return .always;
        if (std.mem.eql(u8, s, "module")) return .module;
        if (std.mem.eql(u8, s, "once")) return .once;
        return null;
    }

    pub fn toString(self: FilterAction) []const u8 {
        return switch (self) {
            .default => "default",
            .@"error" => "error",
            .ignore => "ignore",
            .always => "always",
            .module => "module",
            .once => "once",
        };
    }
};

// ============================================================================
// Warning Filter
// ============================================================================

/// A single warning filter entry
pub const WarningFilter = struct {
    action: FilterAction,
    message: ?[]const u8 = null, // Pattern to match message
    category: WarningCategory = .Warning,
    module: ?[]const u8 = null, // Pattern to match module name
    lineno: ?usize = null, // Specific line number (0 = all)

    pub fn matches(
        self: WarningFilter,
        message: []const u8,
        category: WarningCategory,
        module_name: []const u8,
        lineno: usize,
    ) bool {
        // Check category (must be same or subclass)
        if (!category.isSubclassOf(self.category)) {
            return false;
        }

        // Check message pattern
        if (self.message) |pattern| {
            if (std.mem.indexOf(u8, message, pattern) == null) {
                return false;
            }
        }

        // Check module pattern
        if (self.module) |mod_pattern| {
            if (std.mem.indexOf(u8, module_name, mod_pattern) == null) {
                return false;
            }
        }

        // Check line number
        if (self.lineno) |ln| {
            if (ln != 0 and ln != lineno) {
                return false;
            }
        }

        return true;
    }
};

// ============================================================================
// Warning Record (for CatchWarnings)
// ============================================================================

/// Record of a warning that was issued
pub const WarningRecord = struct {
    message: []const u8,
    category: WarningCategory,
    filename: []const u8,
    lineno: usize,
};
