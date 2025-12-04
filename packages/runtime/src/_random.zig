/// _random - C accelerator module for random
/// Mersenne Twister random number generator
const std = @import("std");

/// Random number generator state
pub const Random = struct {
    rng: std.Random.DefaultPrng,

    const Self = @This();

    /// Initialize with seed
    pub fn init(s: u64) Self {
        return .{
            .rng = std.Random.DefaultPrng.init(s),
        };
    }

    /// Initialize from system entropy
    pub fn initFromEntropy() Self {
        var seed_val: u64 = undefined;
        std.posix.getrandom(std.mem.asBytes(&seed_val)) catch {
            seed_val = @intCast(std.time.milliTimestamp());
        };
        return Self.init(seed_val);
    }

    /// Return random float in [0.0, 1.0)
    pub fn random(self: *Self) f64 {
        return self.rng.random().float(f64);
    }

    /// Return random integer in [a, b] inclusive
    pub fn randint(self: *Self, a: i64, b: i64) i64 {
        if (a > b) return a;
        const range: u64 = @intCast(b - a + 1);
        const r = self.rng.random().uintLessThan(u64, range);
        return a + @as(i64, @intCast(r));
    }

    /// Return random integer in [0, n) exclusive
    pub fn randrange(self: *Self, n: u64) u64 {
        return self.rng.random().uintLessThan(u64, n);
    }

    /// Return random integer in [start, stop) with step
    pub fn randrangeStep(self: *Self, start: i64, stop: i64, step: i64) i64 {
        if (step == 0) return start;
        const count: u64 = @intCast(@divFloor(stop - start - 1, step) + 1);
        if (count == 0) return start;
        const idx = self.randrange(count);
        return start + @as(i64, @intCast(idx)) * step;
    }

    /// Return random float in [a, b)
    pub fn uniform(self: *Self, a: f64, b: f64) f64 {
        return a + (b - a) * self.random();
    }

    /// Return random float with triangular distribution
    pub fn triangular(self: *Self, low: f64, high: f64, mode: ?f64) f64 {
        const u = self.random();
        const c = (mode orelse ((low + high) / 2.0) - low) / (high - low);

        if (u < c) {
            return low + @sqrt(u * (high - low) * (mode orelse ((low + high) / 2.0) - low));
        } else {
            return high - @sqrt((1.0 - u) * (high - low) * (high - (mode orelse ((low + high) / 2.0))));
        }
    }

    /// Return random float with normal distribution
    pub fn gauss(self: *Self, mu: f64, sigma: f64) f64 {
        // Box-Muller transform
        const r1 = self.random();
        const r2 = self.random();
        const z = @sqrt(-2.0 * @log(r1)) * @cos(2.0 * std.math.pi * r2);
        return mu + sigma * z;
    }

    /// Alias for gauss
    pub fn normalvariate(self: *Self, mu: f64, sigma: f64) f64 {
        return self.gauss(mu, sigma);
    }

    /// Return random float with log-normal distribution
    pub fn lognormvariate(self: *Self, mu: f64, sigma: f64) f64 {
        return @exp(self.gauss(mu, sigma));
    }

    /// Return random float with exponential distribution
    pub fn expovariate(self: *Self, lambd: f64) f64 {
        return -@log(1.0 - self.random()) / lambd;
    }

    /// Return random float with von Mises distribution
    pub fn vonmisesvariate(self: *Self, mu: f64, kappa: f64) f64 {
        if (kappa <= 1e-6) {
            return 2.0 * std.math.pi * self.random();
        }

        const s = 0.5 / kappa;
        const r = s + @sqrt(1.0 + s * s);

        while (true) {
            const rand1 = self.random();
            const z = @cos(std.math.pi * rand1);
            const d = z / (r + z);
            const rand2 = self.random();

            if (rand2 < 1.0 - d * d or rand2 <= (1.0 - d) * @exp(d)) {
                const q = 1.0 / r;
                const f = (q + z) / (1.0 + q * z);
                const rand3 = self.random();
                if (rand3 > 0.5) {
                    return @mod(mu + std.math.acos(f), 2.0 * std.math.pi);
                } else {
                    return @mod(mu - std.math.acos(f), 2.0 * std.math.pi);
                }
            }
        }
    }

    /// Return random float with gamma distribution
    pub fn gammavariate(self: *Self, alpha: f64, beta: f64) f64 {
        if (alpha <= 0.0 or beta <= 0.0) return 0.0;

        if (alpha > 1.0) {
            // Uses Ahrens-Dieter method
            const ainv = @sqrt(2.0 * alpha - 1.0);
            const bbb = alpha - std.math.ln(f64, 4.0);
            const ccc = alpha + ainv;

            while (true) {
                const rand1 = self.random();
                if (rand1 < 1e-7 or rand1 > 1.0 - 1e-7) continue;

                const rand2 = 1.0 - self.random();
                const v = @log(rand1 / (1.0 - rand1)) / ainv;
                const x = alpha * @exp(v);
                const z = rand1 * rand1 * rand2;
                const r = bbb + ccc * v - x;

                if (r + 2.504077396776274 - 4.5 * z >= 0.0 or r >= @log(z)) {
                    return x * beta;
                }
            }
        } else if (alpha == 1.0) {
            return -@log(1.0 - self.random()) * beta;
        } else {
            // alpha < 1
            var x: f64 = undefined;
            while (true) {
                const u = self.random();
                const b = (std.math.e + alpha) / std.math.e;
                const p = b * u;

                if (p <= 1.0) {
                    x = std.math.pow(f64, p, 1.0 / alpha);
                } else {
                    x = -@log((b - p) / alpha);
                }

                const rand_check = self.random();
                if (p > 1.0) {
                    if (rand_check <= std.math.pow(f64, x, alpha - 1.0)) break;
                } else if (rand_check <= @exp(-x)) {
                    break;
                }
            }
            return x * beta;
        }
    }

    /// Return random float with beta distribution
    pub fn betavariate(self: *Self, alpha: f64, beta: f64) f64 {
        const y = self.gammavariate(alpha, 1.0);
        if (y == 0.0) return 0.0;
        return y / (y + self.gammavariate(beta, 1.0));
    }

    /// Return random float with Pareto distribution
    pub fn paretovariate(self: *Self, alpha: f64) f64 {
        const u = 1.0 - self.random();
        return 1.0 / std.math.pow(f64, u, 1.0 / alpha);
    }

    /// Return random float with Weibull distribution
    pub fn weibullvariate(self: *Self, alpha: f64, beta: f64) f64 {
        const u = 1.0 - self.random();
        return alpha * std.math.pow(f64, -@log(u), 1.0 / beta);
    }

    /// Choose random element from sequence
    pub fn choice(self: *Self, comptime T: type, seq: []const T) T {
        const idx = self.randrange(seq.len);
        return seq[idx];
    }

    /// Shuffle sequence in place
    pub fn shuffle(self: *Self, comptime T: type, seq: []T) void {
        var i: usize = seq.len;
        while (i > 1) {
            i -= 1;
            const j = self.randrange(i + 1);
            const tmp = seq[i];
            seq[i] = seq[@intCast(j)];
            seq[@intCast(j)] = tmp;
        }
    }

    /// Return k unique random elements from population
    pub fn sample(self: *Self, comptime T: type, population: []const T, k: usize, allocator: std.mem.Allocator) ![]T {
        if (k > population.len) return error.SampleLargerThanPopulation;

        var result = try allocator.alloc(T, k);
        var pool = try allocator.alloc(T, population.len);
        defer allocator.free(pool);
        @memcpy(pool, population);

        for (0..k) |i| {
            const j = self.randrange(population.len - i);
            result[i] = pool[@intCast(j)];
            pool[@intCast(j)] = pool[population.len - i - 1];
        }

        return result;
    }

    /// Set seed
    pub fn seed(self: *Self, s: u64) void {
        self.rng = std.Random.DefaultPrng.init(s);
    }

    /// Get state (for getstate())
    pub fn getstate(self: Self) u64 {
        // Simplified - real implementation would save full MT state
        _ = self;
        return 0;
    }

    /// Set state (for setstate())
    pub fn setstate(self: *Self, state: u64) void {
        // Simplified
        self.rng = std.Random.DefaultPrng.init(state);
    }

    /// Get random bytes
    pub fn randbytes(self: *Self, n: usize, allocator: std.mem.Allocator) ![]u8 {
        const result = try allocator.alloc(u8, n);
        self.rng.random().bytes(result);
        return result;
    }
};

/// Module-level random instance
var global_random: ?Random = null;

pub fn getGlobalRandom() *Random {
    if (global_random == null) {
        global_random = Random.initFromEntropy();
    }
    return &global_random.?;
}

// Convenience functions using global random
pub fn random() f64 {
    return getGlobalRandom().random();
}

pub fn randint(a: i64, b: i64) i64 {
    return getGlobalRandom().randint(a, b);
}

pub fn uniform(a: f64, b: f64) f64 {
    return getGlobalRandom().uniform(a, b);
}

pub fn choice(comptime T: type, seq: []const T) T {
    return getGlobalRandom().choice(T, seq);
}

pub fn shuffle(comptime T: type, seq: []T) void {
    getGlobalRandom().shuffle(T, seq);
}

pub fn seed(s: u64) void {
    getGlobalRandom().seed(s);
}

// ============================================================================
// Tests
// ============================================================================

test "random in range" {
    var rng = Random.init(12345);

    for (0..100) |_| {
        const r = rng.random();
        try std.testing.expect(r >= 0.0 and r < 1.0);
    }
}

test "randint" {
    var rng = Random.init(12345);

    for (0..100) |_| {
        const r = rng.randint(10, 20);
        try std.testing.expect(r >= 10 and r <= 20);
    }
}

test "uniform" {
    var rng = Random.init(12345);

    for (0..100) |_| {
        const r = rng.uniform(5.0, 10.0);
        try std.testing.expect(r >= 5.0 and r < 10.0);
    }
}

test "choice" {
    var rng = Random.init(12345);
    const items = [_]i32{ 1, 2, 3, 4, 5 };

    for (0..100) |_| {
        const c = rng.choice(i32, &items);
        try std.testing.expect(c >= 1 and c <= 5);
    }
}

test "shuffle" {
    var rng = Random.init(12345);
    var items = [_]i32{ 1, 2, 3, 4, 5 };
    const original = [_]i32{ 1, 2, 3, 4, 5 };

    rng.shuffle(i32, &items);

    // Check same elements (just reordered)
    var sum: i32 = 0;
    for (items) |i| sum += i;
    var orig_sum: i32 = 0;
    for (original) |i| orig_sum += i;
    try std.testing.expectEqual(orig_sum, sum);
}

test "gauss distribution" {
    var rng = Random.init(12345);

    // Generate many samples and check mean is roughly correct
    var sum: f64 = 0;
    const n: usize = 1000;
    for (0..n) |_| {
        sum += rng.gauss(100.0, 15.0);
    }
    const mean = sum / @as(f64, @floatFromInt(n));
    // Mean should be close to 100 (within ~3 standard errors)
    try std.testing.expect(mean > 95.0 and mean < 105.0);
}
