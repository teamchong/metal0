//! Email policy classes
//!
//! Provides policy classes for controlling email message behavior.

const std = @import("std");

/// Email policy
pub const Policy = struct {
    max_line_length: usize,
    utf8: bool,
    cte_type: []const u8,

    pub const default = Policy{
        .max_line_length = 78,
        .utf8 = false,
        .cte_type = "7bit",
    };

    pub const compat32 = Policy{
        .max_line_length = 998,
        .utf8 = false,
        .cte_type = "7bit",
    };

    pub const smtp = Policy{
        .max_line_length = 998,
        .utf8 = false,
        .cte_type = "7bit",
    };

    pub const smtputf8 = Policy{
        .max_line_length = 998,
        .utf8 = true,
        .cte_type = "8bit",
    };
};

/// Email policy (alias)
pub const EmailPolicy = Policy;
