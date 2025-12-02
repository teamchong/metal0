/// Python sre_constants module - Internal support module for sre
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "MAGIC", h.U32(20171005) }, .{ "MAXREPEAT", h.U32(4294967295) }, .{ "MAXGROUPS", h.U32(100) },
    .{ "OPCODES", h.c("&[_][]const u8{ \"FAILURE\", \"SUCCESS\", \"ANY\", \"ANY_ALL\", \"ASSERT\", \"ASSERT_NOT\", \"AT\", \"BRANCH\", \"CALL\", \"CATEGORY\", \"CHARSET\", \"BIGCHARSET\", \"GROUPREF\", \"GROUPREF_EXISTS\", \"IN\", \"INFO\", \"JUMP\", \"LITERAL\", \"MARK\", \"MAX_UNTIL\", \"MIN_UNTIL\", \"NOT_LITERAL\", \"NEGATE\", \"RANGE\", \"REPEAT\", \"REPEAT_ONE\", \"SUBPATTERN\", \"MIN_REPEAT_ONE\", \"ATOMIC_GROUP\", \"POSSESSIVE_REPEAT\", \"POSSESSIVE_REPEAT_ONE\" }") },
    .{ "ATCODES", h.c("&[_][]const u8{ \"AT_BEGINNING\", \"AT_BEGINNING_LINE\", \"AT_BEGINNING_STRING\", \"AT_BOUNDARY\", \"AT_NON_BOUNDARY\", \"AT_END\", \"AT_END_LINE\", \"AT_END_STRING\" }") },
    .{ "CHCODES", h.c("&[_][]const u8{ \"CATEGORY_DIGIT\", \"CATEGORY_NOT_DIGIT\", \"CATEGORY_SPACE\", \"CATEGORY_NOT_SPACE\", \"CATEGORY_WORD\", \"CATEGORY_NOT_WORD\", \"CATEGORY_LINEBREAK\", \"CATEGORY_NOT_LINEBREAK\" }") },
    .{ "FAILURE", h.U32(0) }, .{ "SUCCESS", h.U32(1) }, .{ "ANY", h.U32(2) }, .{ "ANY_ALL", h.U32(3) },
    .{ "ASSERT", h.U32(4) }, .{ "ASSERT_NOT", h.U32(5) }, .{ "AT", h.U32(6) }, .{ "BRANCH", h.U32(7) },
    .{ "CALL", h.U32(8) }, .{ "CATEGORY", h.U32(9) }, .{ "CHARSET", h.U32(10) }, .{ "BIGCHARSET", h.U32(11) },
    .{ "GROUPREF", h.U32(12) }, .{ "GROUPREF_EXISTS", h.U32(13) }, .{ "IN", h.U32(14) }, .{ "INFO", h.U32(15) },
    .{ "JUMP", h.U32(16) }, .{ "LITERAL", h.U32(17) }, .{ "MARK", h.U32(18) }, .{ "MAX_UNTIL", h.U32(19) },
    .{ "MIN_UNTIL", h.U32(20) }, .{ "NOT_LITERAL", h.U32(21) }, .{ "NEGATE", h.U32(22) }, .{ "RANGE", h.U32(23) },
    .{ "REPEAT", h.U32(24) }, .{ "REPEAT_ONE", h.U32(25) }, .{ "SUBPATTERN", h.U32(26) }, .{ "MIN_REPEAT_ONE", h.U32(27) },
    .{ "SRE_FLAG_TEMPLATE", h.U32(1) }, .{ "SRE_FLAG_IGNORECASE", h.U32(2) }, .{ "SRE_FLAG_LOCALE", h.U32(4) },
    .{ "SRE_FLAG_MULTILINE", h.U32(8) }, .{ "SRE_FLAG_DOTALL", h.U32(16) }, .{ "SRE_FLAG_UNICODE", h.U32(32) },
    .{ "SRE_FLAG_VERBOSE", h.U32(64) }, .{ "SRE_FLAG_DEBUG", h.U32(128) }, .{ "SRE_FLAG_ASCII", h.U32(256) },
    .{ "SRE_INFO_PREFIX", h.U32(1) }, .{ "SRE_INFO_LITERAL", h.U32(2) }, .{ "SRE_INFO_CHARSET", h.U32(4) },
    .{ "error", h.err("SreError") },
});
