// TODO: Implement SIMD dispatch
pub fn hasEscapes(data: []const u8) bool {
    for (data) |c| {
        if (c == '\\') return true;
    }
    return false;
}

pub fn findClosingQuote(data: []const u8, start: usize) ?usize {
    var i = start;
    while (i < data.len) : (i += 1) {
        if (data[i] == '"') return i;
        if (data[i] == '\\') i += 1; // Skip escaped character
    }
    return null;
}
