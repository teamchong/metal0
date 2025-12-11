/// Combinatoric Iterators - permutations, combinations, products
const std = @import("std");

// ============================================================================
// Combinatoric Iterators
// ============================================================================

/// product(*iterables, repeat=1) - Cartesian product of input iterables
/// Returns all combinations as a flat iterator
pub fn ProductIterator(comptime T: type, comptime N: usize) type {
    return struct {
        iterables: [N][]const T,
        indices: [N]usize,
        done: bool,

        const Self = @This();

        pub fn init(iterables: [N][]const T) Self {
            var indices: [N]usize = undefined;
            for (&indices) |*idx| idx.* = 0;

            // Check if any iterable is empty
            var done = false;
            for (iterables) |iter| {
                if (iter.len == 0) {
                    done = true;
                    break;
                }
            }

            return .{ .iterables = iterables, .indices = indices, .done = done };
        }

        pub fn next(self: *Self) ?[N]T {
            if (self.done) return null;

            // Get current combination
            var result: [N]T = undefined;
            for (0..N) |i| {
                result[i] = self.iterables[i][self.indices[i]];
            }

            // Increment indices (like counting in mixed radix)
            var i: usize = N;
            while (i > 0) {
                i -= 1;
                self.indices[i] += 1;
                if (self.indices[i] < self.iterables[i].len) {
                    break;
                }
                self.indices[i] = 0;
                if (i == 0) {
                    self.done = true;
                }
            }

            return result;
        }
    };
}

/// permutations(iterable, r=None) - Return successive r-length permutations
pub fn PermutationsIterator(comptime T: type, comptime R: usize) type {
    return struct {
        data: []const T,
        indices: [R]usize,
        cycles: [R]usize,
        done: bool,

        const Self = @This();

        pub fn init(data: []const T) Self {
            const n = data.len;
            var indices: [R]usize = undefined;
            var cycles: [R]usize = undefined;

            if (R > n) {
                return .{ .data = data, .indices = indices, .cycles = cycles, .done = true };
            }

            for (0..R) |i| {
                indices[i] = i;
                cycles[i] = n - i;
            }

            return .{ .data = data, .indices = indices, .cycles = cycles, .done = false };
        }

        pub fn next(self: *Self) ?[R]T {
            if (self.done) return null;

            // Get current permutation
            var result: [R]T = undefined;
            for (0..R) |i| {
                result[i] = self.data[self.indices[i]];
            }

            // Generate next permutation
            var i: usize = R;
            while (i > 0) {
                i -= 1;
                self.cycles[i] -= 1;
                if (self.cycles[i] == 0) {
                    // Rotate indices[i:] left by 1
                    const temp = self.indices[i];
                    var j = i;
                    while (j + 1 < self.data.len and j + 1 < R + (self.data.len - R)) {
                        if (j + 1 < R) {
                            self.indices[j] = self.indices[j + 1];
                        }
                        j += 1;
                    }
                    if (i < R) {
                        self.indices[if (R > 1) R - 1 else 0] = temp;
                    }
                    self.cycles[i] = self.data.len - i;
                } else {
                    // Swap
                    const j = self.data.len - self.cycles[i];
                    const temp = self.indices[i];
                    self.indices[i] = if (j < R) self.indices[j] else j;
                    if (j < R) self.indices[j] = temp;
                    return result;
                }
            }

            self.done = true;
            return result;
        }
    };
}

/// combinations(iterable, r) - Return r-length combinations
pub fn CombinationsIterator(comptime T: type, comptime R: usize) type {
    return struct {
        data: []const T,
        indices: [R]usize,
        done: bool,

        const Self = @This();

        pub fn init(data: []const T) Self {
            var indices: [R]usize = undefined;

            if (R > data.len) {
                return .{ .data = data, .indices = indices, .done = true };
            }

            for (0..R) |i| {
                indices[i] = i;
            }

            return .{ .data = data, .indices = indices, .done = false };
        }

        pub fn next(self: *Self) ?[R]T {
            if (self.done) return null;

            // Get current combination
            var result: [R]T = undefined;
            for (0..R) |i| {
                result[i] = self.data[self.indices[i]];
            }

            // Generate next combination
            var i: usize = R;
            while (i > 0) {
                i -= 1;
                if (self.indices[i] != i + self.data.len - R) {
                    self.indices[i] += 1;
                    for (i + 1..R) |j| {
                        self.indices[j] = self.indices[j - 1] + 1;
                    }
                    return result;
                }
            }

            self.done = true;
            return result;
        }
    };
}
