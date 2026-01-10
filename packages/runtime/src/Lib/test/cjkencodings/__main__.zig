//! test.cjkencodings - CJK encoding test data
const std = @import("std");

pub const Encoding = struct {
    name: []const u8,
    aliases: []const []const u8 = &.{},
    codec: []const u8,
    
    pub fn init(name: []const u8, codec: []const u8) @This() {
        return .{ .name = name, .codec = codec };
    }
};

pub const encodings = [_]Encoding{
    Encoding.init("gb2312", "gb2312"),
    Encoding.init("gbk", "gbk"),
    Encoding.init("gb18030", "gb18030"),
    Encoding.init("big5", "big5"),
    Encoding.init("big5hkscs", "big5hkscs"),
    Encoding.init("euc_jp", "euc_jp"),
    Encoding.init("euc_jis_2004", "euc_jis_2004"),
    Encoding.init("euc_jisx0213", "euc_jisx0213"),
    Encoding.init("euc_kr", "euc_kr"),
    Encoding.init("iso2022_jp", "iso2022_jp"),
    Encoding.init("iso2022_jp_1", "iso2022_jp_1"),
    Encoding.init("iso2022_jp_2", "iso2022_jp_2"),
    Encoding.init("iso2022_jp_3", "iso2022_jp_3"),
    Encoding.init("iso2022_kr", "iso2022_kr"),
    Encoding.init("johab", "johab"),
    Encoding.init("shift_jis", "shift_jis"),
    Encoding.init("shift_jis_2004", "shift_jis_2004"),
    Encoding.init("shift_jisx0213", "shift_jisx0213"),
};

test "encodings_count" {
    try std.testing.expect(encodings.len > 0);
}

test "encoding_init" {
    const enc = Encoding.init("utf-8", "utf_8");
    try std.testing.expectEqualStrings("utf-8", enc.name);
}
