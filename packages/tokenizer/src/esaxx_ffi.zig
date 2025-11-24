const std = @import("std");
const Allocator = std.mem.Allocator;

// C ABI structures matching Rust FFI
pub const SubstringResult = extern struct {
    string_ptr: [*]const u8,
    string_len: usize,
    freq: u32,
};

pub const SubstringList = extern struct {
    items: [*]SubstringResult,
    len: usize,
};

// External functions from Rust esaxx-rs FFI
extern fn esaxx_extract_substrings(text: [*]const u8, text_len: usize) ?*SubstringList;
extern fn esaxx_free_results(list: *SubstringList) void;

pub const SubstringFreq = struct {
    string: []const u8,
    freq: u32,

    pub fn deinit(self: *SubstringFreq, allocator: Allocator) void {
        allocator.free(self.string);
    }
};

/// Extract frequent substrings using esaxx-rs library via FFI
pub fn extractSubstrings(
    allocator: Allocator,
    text: []const u8,
) ![]SubstringFreq {
    // Call Rust FFI
    const list_ptr = esaxx_extract_substrings(text.ptr, text.len) orelse {
        return error.EsaxxFailed;
    };
    defer esaxx_free_results(list_ptr);

    const list = list_ptr.*;

    // Convert to Zig array
    var results = std.ArrayList(SubstringFreq){};
    defer results.deinit(allocator);

    const items = list.items[0..list.len];
    for (items) |item| {
        const string_slice = item.string_ptr[0..item.string_len];

        // Copy the string (Rust will free its version)
        const string_copy = try allocator.dupe(u8, string_slice);

        try results.append(allocator, SubstringFreq{
            .string = string_copy,
            .freq = item.freq,
        });
    }

    return try results.toOwnedSlice(allocator);
}
