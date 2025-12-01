//! Gzip test runner - runs tests from gzip.zig
const gzip = @import("gzip.zig");

// Re-export tests from gzip module
test {
    _ = gzip;
}
