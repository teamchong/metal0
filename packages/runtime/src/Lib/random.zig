//! CPython source: Lib/random.py
//!
//! Provides pseudo-random number generators for various distributions.
//!
//! Mirrors: CPython Lib/random.py

const std = @import("std");
const math = std.math;

// ============================================================================
// Random Generator
// ============================================================================

/// Random number generator (Mersenne Twister)
pub const Random = struct {
    const Self = @This();

    rng: std.Random.DefaultPrng,
    gauss_next: ?f64,

    pub fn init(init_seed: ?u64) Self {
        const actual_seed = init_seed orelse @as(u64, @intCast(std.time.timestamp()));
        return .{
            .rng = std.Random.DefaultPrng.init(actual_seed),
            .gauss_next = null,
        };
    }

    /// Seed the generator
    pub fn seedWith(self: *Self, new_seed: u64) void {
        self.rng = std.Random.DefaultPrng.init(new_seed);
        self.gauss_next = null;
    }

    /// Get the underlying random interface
    pub fn random(self: *Self) std.Random {
        return self.rng.random();
    }

    // ========================================================================
    // Integer Methods
    // ========================================================================

    /// Return random integer in range [a, b], including both end points
    pub fn randint(self: *Self, a: i64, b: i64) i64 {
        const range: u64 = @intCast(b - a + 1);
        return a + @as(i64, @intCast(self.rng.random().uintLessThan(u64, range)));
    }

    /// Return random integer in range [0, n)
    pub fn randrange(self: *Self, start: i64, stop: ?i64, step: ?i64) i64 {
        const actual_stop = stop orelse {
            // randrange(n) -> [0, n)
            return @as(i64, @intCast(self.rng.random().uintLessThan(u64, @intCast(start))));
        };

        const actual_step = step orelse 1;
        const n = @divTrunc(actual_stop - start + actual_step - 1, actual_step);

        if (n <= 0) return start;

        const idx: i64 = @intCast(self.rng.random().uintLessThan(u64, @intCast(n)));
        return start + idx * actual_step;
    }

    /// Return a random n-bit integer (k can be 0-64)
    pub fn getrandbits(self: *Self, k: u7) u64 {
        if (k == 0) return 0;
        if (k == 64) return self.rng.random().int(u64);
        // k is 1-63, so shift amount 64-k is 1-63 which fits in u6
        return self.rng.random().int(u64) >> @as(u6, @intCast(64 - @as(u8, k)));
    }

    // ========================================================================
    // Sequence Methods
    // ========================================================================

    /// Choose a random element from a non-empty sequence
    pub fn choice(self: *Self, comptime T: type, seq: []const T) T {
        const idx = self.rng.random().uintLessThan(usize, seq.len);
        return seq[idx];
    }

    /// Choose k unique random elements from a sequence
    pub fn sample(self: *Self, comptime T: type, allocator: std.mem.Allocator, population: []const T, k: usize) ![]T {
        if (k > population.len) return error.SampleLargerThanPopulation;

        var result = try allocator.alloc(T, k);
        errdefer allocator.free(result);

        // For small k, use selection sampling
        if (k * 3 < population.len) {
            var selected = std.AutoHashMap(usize, void).init(allocator);
            defer selected.deinit();

            var i: usize = 0;
            while (i < k) {
                const idx = self.rng.random().uintLessThan(usize, population.len);
                if (!selected.contains(idx)) {
                    try selected.put(idx, {});
                    result[i] = population[idx];
                    i += 1;
                }
            }
        } else {
            // For large k, shuffle a copy
            var pool = try allocator.alloc(T, population.len);
            defer allocator.free(pool);
            @memcpy(pool, population);

            for (0..k) |i| {
                const j = i + self.rng.random().uintLessThan(usize, population.len - i);
                const tmp = pool[i];
                pool[i] = pool[j];
                pool[j] = tmp;
                result[i] = pool[i];
            }
        }

        return result;
    }

    /// Choose k elements with replacement (can repeat)
    pub fn choices(self: *Self, comptime T: type, allocator: std.mem.Allocator, population: []const T, weights: ?[]const f64, k: usize) ![]T {
        var result = try allocator.alloc(T, k);
        errdefer allocator.free(result);

        if (weights) |w| {
            // Calculate cumulative weights
            var cum_weights = try allocator.alloc(f64, w.len);
            defer allocator.free(cum_weights);

            var total: f64 = 0;
            for (w, 0..) |weight, i| {
                total += weight;
                cum_weights[i] = total;
            }

            // Select k items
            for (0..k) |i| {
                const r = self.uniformFloat(0, total);
                for (cum_weights, 0..) |cw, j| {
                    if (r <= cw) {
                        result[i] = population[j];
                        break;
                    }
                }
            }
        } else {
            // Uniform selection
            for (0..k) |i| {
                result[i] = self.choice(T, population);
            }
        }

        return result;
    }

    /// Shuffle a slice in-place
    pub fn shuffle(self: *Self, comptime T: type, x: []T) void {
        var i = x.len;
        while (i > 1) {
            i -= 1;
            const j = self.rng.random().uintLessThan(usize, i + 1);
            const tmp = x[i];
            x[i] = x[j];
            x[j] = tmp;
        }
    }

    // ========================================================================
    // Float Methods
    // ========================================================================

    /// Return random float in [0.0, 1.0)
    pub fn randomFloat(self: *Self) f64 {
        return self.rng.random().float(f64);
    }

    /// Return random float in [a, b) or [a, b] depending on rounding
    pub fn uniform(self: *Self, a: f64, b: f64) f64 {
        return a + (b - a) * self.randomFloat();
    }

    /// Alias for uniform
    pub fn uniformFloat(self: *Self, a: f64, b: f64) f64 {
        return self.uniform(a, b);
    }

    /// Return random float with triangular distribution
    pub fn triangular(self: *Self, low: f64, high: f64, mode: ?f64) f64 {
        const c = if (mode) |m| (m - low) / (high - low) else 0.5;
        const u = self.randomFloat();

        if (u <= c) {
            return low + @sqrt(u * (high - low) * (mode orelse ((high + low) / 2) - low));
        } else {
            return high - @sqrt((1.0 - u) * (high - low) * (high - (mode orelse ((high + low) / 2))));
        }
    }

    /// Return random float with beta distribution
    pub fn betavariate(self: *Self, alpha: f64, beta: f64) f64 {
        const y = self.gammavariate(alpha, 1.0);
        if (y == 0) return 0.0;
        return y / (y + self.gammavariate(beta, 1.0));
    }

    /// Return random float with exponential distribution
    pub fn expovariate(self: *Self, lambd: f64) f64 {
        return -@log(1.0 - self.randomFloat()) / lambd;
    }

    /// Return random float with gamma distribution
    pub fn gammavariate(self: *Self, alpha: f64, beta: f64) f64 {
        if (alpha <= 0.0 or beta <= 0.0) return 0.0;

        if (alpha > 1.0) {
            // Uses R.C.H. Cheng, "The generation of Gamma
            // variables with non-integral shape parameters"
            const ainv = @sqrt(2.0 * alpha - 1.0);
            const bbb = alpha - math.ln(f64, 4.0);
            const ccc = alpha + ainv;

            while (true) {
                const r1 = self.randomFloat();
                if (r1 < 1e-7 or r1 > 0.9999999) continue;

                const r2 = 1.0 - self.randomFloat();
                const v = @log(r1 / (1.0 - r1)) / ainv;
                const x = alpha * @exp(v);
                const z = r1 * r1 * r2;
                const r = bbb + ccc * v - x;

                if (r + 2.504077396776274 - 4.5 * z >= 0.0 or r >= @log(z)) {
                    return x * beta;
                }
            }
        } else if (alpha == 1.0) {
            return -@log(1.0 - self.randomFloat()) * beta;
        } else {
            // alpha < 1
            while (true) {
                const u = self.randomFloat();
                const b = (math.e + alpha) / math.e;
                const p = b * u;

                if (p <= 1.0) {
                    const x = math.pow(f64, p, 1.0 / alpha);
                    if (self.randomFloat() <= @exp(-x)) {
                        return x * beta;
                    }
                } else {
                    const x = -@log((b - p) / alpha);
                    if (self.randomFloat() <= math.pow(f64, x, alpha - 1.0)) {
                        return x * beta;
                    }
                }
            }
        }
    }

    /// Return random float with Gaussian (normal) distribution
    pub fn gauss(self: *Self, mu: f64, sigma: f64) f64 {
        // Use Box-Muller transform
        if (self.gauss_next) |next| {
            self.gauss_next = null;
            return mu + next * sigma;
        }

        const r1 = self.randomFloat();
        const r2 = self.randomFloat();

        const z0 = @sqrt(-2.0 * @log(r1)) * @cos(2.0 * math.pi * r2);
        const z1 = @sqrt(-2.0 * @log(r1)) * @sin(2.0 * math.pi * r2);

        self.gauss_next = z1;
        return mu + z0 * sigma;
    }

    /// Alias for gauss
    pub fn normalvariate(self: *Self, mu: f64, sigma: f64) f64 {
        return self.gauss(mu, sigma);
    }

    /// Return random float with log-normal distribution
    pub fn lognormvariate(self: *Self, mu: f64, sigma: f64) f64 {
        return @exp(self.normalvariate(mu, sigma));
    }

    /// Return random float with von Mises distribution
    pub fn vonmisesvariate(self: *Self, mu: f64, kappa: f64) f64 {
        if (kappa <= 1e-6) {
            return 2.0 * math.pi * self.randomFloat();
        }

        const s = 0.5 / kappa;
        const r = s + @sqrt(1.0 + s * s);

        while (true) {
            const r1 = self.randomFloat();
            const z = @cos(math.pi * r1);
            const d = z / (r + z);
            const r2 = self.randomFloat();

            if (r2 < 1.0 - d * d or r2 <= (1.0 - d) * @exp(d)) {
                const q = 1.0 / r;
                const f = (q + z) / (1.0 + q * z);
                const r3 = self.randomFloat();

                if (r3 > 0.5) {
                    return @mod(mu + math.acos(f), 2.0 * math.pi);
                } else {
                    return @mod(mu - math.acos(f), 2.0 * math.pi);
                }
            }
        }
    }

    /// Return random float with Pareto distribution
    pub fn paretovariate(self: *Self, alpha: f64) f64 {
        return 1.0 / math.pow(f64, 1.0 - self.randomFloat(), 1.0 / alpha);
    }

    /// Return random float with Weibull distribution
    pub fn weibullvariate(self: *Self, alpha: f64, beta: f64) f64 {
        return alpha * math.pow(f64, -@log(1.0 - self.randomFloat()), 1.0 / beta);
    }
};

// ============================================================================
// Module-Level State
// ============================================================================

var default_instance: ?Random = null;

fn getDefaultInstance() *Random {
    if (default_instance == null) {
        default_instance = Random.init(null);
    }
    return &default_instance.?;
}

// ============================================================================
// Module-Level Functions
// ============================================================================

/// Seed the default generator
pub fn seed(s: ?u64) void {
    if (s) |val| {
        getDefaultInstance().seedWith(val);
    } else {
        default_instance = Random.init(null);
    }
}

/// Return random integer in [a, b]
pub fn randint(a: i64, b: i64) i64 {
    return getDefaultInstance().randint(a, b);
}

/// Return random integer in range
pub fn randrange(start: i64, stop: ?i64, step: ?i64) i64 {
    return getDefaultInstance().randrange(start, stop, step);
}

/// Return n random bits (k should be 0-64, larger values are clamped)
pub fn getrandbits(k: anytype) u64 {
    const T = @TypeOf(k);
    const k_val: u7 = switch (@typeInfo(T)) {
        .int, .comptime_int => blk: {
            if (k < 0) break :blk 0;
            if (k > 64) break :blk 64;
            break :blk @intCast(k);
        },
        else => @compileError("getrandbits expects an integer type"),
    };
    return getDefaultInstance().getrandbits(k_val);
}

/// Choose a random element
pub fn choice(comptime T: type, seq: []const T) T {
    return getDefaultInstance().choice(T, seq);
}

/// Choose k unique random elements
pub fn sample(comptime T: type, allocator: std.mem.Allocator, population: []const T, k: usize) ![]T {
    return getDefaultInstance().sample(T, allocator, population, k);
}

/// Choose k elements with replacement
pub fn choices(comptime T: type, allocator: std.mem.Allocator, population: []const T, weights: ?[]const f64, k: usize) ![]T {
    return getDefaultInstance().choices(T, allocator, population, weights, k);
}

/// Shuffle a slice in place
pub fn shuffle(comptime T: type, x: []T) void {
    getDefaultInstance().shuffle(T, x);
}

/// Return random float in [0.0, 1.0)
pub fn random() f64 {
    return getDefaultInstance().randomFloat();
}

/// Return random float in [a, b]
pub fn uniform(a: f64, b: f64) f64 {
    return getDefaultInstance().uniform(a, b);
}

/// Return random float with triangular distribution
pub fn triangular(low: f64, high: f64, mode: ?f64) f64 {
    return getDefaultInstance().triangular(low, high, mode);
}

/// Return random float with beta distribution
pub fn betavariate(alpha: f64, beta: f64) f64 {
    return getDefaultInstance().betavariate(alpha, beta);
}

/// Return random float with exponential distribution
pub fn expovariate(lambd: f64) f64 {
    return getDefaultInstance().expovariate(lambd);
}

/// Return random float with gamma distribution
pub fn gammavariate(alpha: f64, beta: f64) f64 {
    return getDefaultInstance().gammavariate(alpha, beta);
}

/// Return random float with Gaussian distribution
pub fn gauss(mu: f64, sigma: f64) f64 {
    return getDefaultInstance().gauss(mu, sigma);
}

/// Return random float with normal distribution
pub fn normalvariate(mu: f64, sigma: f64) f64 {
    return getDefaultInstance().normalvariate(mu, sigma);
}

/// Return random float with log-normal distribution
pub fn lognormvariate(mu: f64, sigma: f64) f64 {
    return getDefaultInstance().lognormvariate(mu, sigma);
}

/// Return random float with von Mises distribution
pub fn vonmisesvariate(mu: f64, kappa: f64) f64 {
    return getDefaultInstance().vonmisesvariate(mu, kappa);
}

/// Return random float with Pareto distribution
pub fn paretovariate(alpha: f64) f64 {
    return getDefaultInstance().paretovariate(alpha);
}

/// Return random float with Weibull distribution
pub fn weibullvariate(alpha: f64, beta: f64) f64 {
    return getDefaultInstance().weibullvariate(alpha, beta);
}

// ============================================================================
// Tests
// ============================================================================

test "Random init" {
    var rng = Random.init(12345);
    const r1 = rng.randomFloat();
    const r2 = rng.randomFloat();
    try std.testing.expect(r1 != r2);
    try std.testing.expect(r1 >= 0.0 and r1 < 1.0);
}

test "randint" {
    var rng = Random.init(12345);
    for (0..100) |_| {
        const val = rng.randint(1, 10);
        try std.testing.expect(val >= 1 and val <= 10);
    }
}

test "choice" {
    var rng = Random.init(12345);
    const items = [_]i32{ 1, 2, 3, 4, 5 };
    for (0..100) |_| {
        const val = rng.choice(i32, &items);
        try std.testing.expect(val >= 1 and val <= 5);
    }
}

test "shuffle" {
    var rng = Random.init(12345);
    var arr = [_]i32{ 1, 2, 3, 4, 5 };
    rng.shuffle(i32, &arr);
    // Just check it still has the same elements
    var sum: i32 = 0;
    for (arr) |v| {
        sum += v;
    }
    try std.testing.expectEqual(@as(i32, 15), sum);
}

test "uniform" {
    var rng = Random.init(12345);
    for (0..100) |_| {
        const val = rng.uniform(5.0, 10.0);
        try std.testing.expect(val >= 5.0 and val <= 10.0);
    }
}

test "gauss" {
    var rng = Random.init(12345);
    var sum: f64 = 0;
    const n: usize = 1000;
    for (0..n) |_| {
        sum += rng.gauss(0, 1);
    }
    // Mean should be close to 0
    const mean = sum / @as(f64, @floatFromInt(n));
    try std.testing.expect(@abs(mean) < 0.1);
}

test "sample" {
    var rng = Random.init(12345);
    const population = [_]i32{ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 };
    const result = try rng.sample(i32, std.testing.allocator, &population, 3);
    defer std.testing.allocator.free(result);

    try std.testing.expectEqual(@as(usize, 3), result.len);

    // Check all elements are from population
    for (result) |val| {
        var found = false;
        for (population) |p| {
            if (p == val) {
                found = true;
                break;
            }
        }
        try std.testing.expect(found);
    }
}
