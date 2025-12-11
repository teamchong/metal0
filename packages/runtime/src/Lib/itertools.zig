/// itertools module - Functions creating iterators for efficient looping
/// CPython Reference: https://docs.python.org/3.12/library/itertools.html
///
/// This module is split into focused sub-modules:
/// - infinite: Infinite iterators (count, cycle, repeat)
/// - terminating: Iterators terminating on shortest input (chain, compress, dropwhile, etc.)
/// - combinatoric: Combinatoric iterators (product, permutations, combinations)
/// - grouping: Grouping iterators (groupby, starmap, batched)
/// - utils: Utility functions (collect, product runtime function)

const std = @import("std");

// Reuse existing iterator infrastructure
const iterobject = @import("../Python/iterobject.zig");
pub const SequenceIterator = iterobject.SequenceIterator;

// Import submodules
const infinite = @import("itertools/infinite.zig");
const terminating = @import("itertools/terminating.zig");
const combinatoric = @import("itertools/combinatoric.zig");
const grouping = @import("itertools/grouping.zig");
const utils = @import("itertools/utils.zig");

// ============================================================================
// Re-export Infinite Iterators
// ============================================================================
pub const CountIterator = infinite.CountIterator;
pub const count = infinite.count;
pub const CycleIterator = infinite.CycleIterator;
pub const cycle = infinite.cycle;
pub const RepeatIterator = infinite.RepeatIterator;
pub const repeat = infinite.repeat;

// ============================================================================
// Re-export Terminating Iterators
// ============================================================================
pub const AccumulateIterator = terminating.AccumulateIterator;
pub const ChainIterator = terminating.ChainIterator;
pub const chain = terminating.chain;
pub const chainFromIterable = terminating.chainFromIterable;
pub const ChainFromIterableIterator = terminating.ChainFromIterableIterator;
pub const CompressIterator = terminating.CompressIterator;
pub const compress = terminating.compress;
pub const DropWhileIterator = terminating.DropWhileIterator;
pub const dropwhile = terminating.dropwhile;
pub const FilterFalseIterator = terminating.FilterFalseIterator;
pub const filterfalse = terminating.filterfalse;
pub const ISliceIterator = terminating.ISliceIterator;
pub const islice = terminating.islice;
pub const isliceEx = terminating.isliceEx;
pub const PairwiseIterator = terminating.PairwiseIterator;
pub const pairwise = terminating.pairwise;
pub const TakeWhileIterator = terminating.TakeWhileIterator;
pub const takewhile = terminating.takewhile;
pub const ZipLongestIterator = terminating.ZipLongestIterator;
pub const zip_longest = terminating.zip_longest;

// ============================================================================
// Re-export Combinatoric Iterators
// ============================================================================
pub const ProductIterator = combinatoric.ProductIterator;
pub const PermutationsIterator = combinatoric.PermutationsIterator;
pub const CombinationsIterator = combinatoric.CombinationsIterator;

// ============================================================================
// Re-export Grouping Iterators
// ============================================================================
pub const GroupByIterator = grouping.GroupByIterator;
pub const groupby = grouping.groupby;
pub const identity = grouping.identity;
pub const StarMapIterator = grouping.StarMapIterator;
pub const starmap = grouping.starmap;
pub const BatchedIterator = grouping.BatchedIterator;
pub const batched = grouping.batched;

// ============================================================================
// Re-export Utilities
// ============================================================================
pub const collect = utils.collect;
pub const product = utils.product;

// ============================================================================
// Tests
// ============================================================================

test "count iterator" {
    var c = count(i32, 10, 2);
    try std.testing.expectEqual(@as(i32, 10), c.next());
    try std.testing.expectEqual(@as(i32, 12), c.next());
    try std.testing.expectEqual(@as(i32, 14), c.next());
}

test "cycle iterator" {
    var cyc = cycle(i32, &[_]i32{ 1, 2, 3 });
    try std.testing.expectEqual(@as(?i32, 1), cyc.next());
    try std.testing.expectEqual(@as(?i32, 2), cyc.next());
    try std.testing.expectEqual(@as(?i32, 3), cyc.next());
    try std.testing.expectEqual(@as(?i32, 1), cyc.next());
}

test "repeat iterator" {
    var r = repeat(i32, 42, 3);
    try std.testing.expectEqual(@as(?i32, 42), r.next());
    try std.testing.expectEqual(@as(?i32, 42), r.next());
    try std.testing.expectEqual(@as(?i32, 42), r.next());
    try std.testing.expectEqual(@as(?i32, null), r.next());
}

test "chain iterator" {
    const a = [_]i32{ 1, 2 };
    const b = [_]i32{ 3, 4, 5 };
    var ch = chain(i32, &[_][]const i32{ &a, &b });
    try std.testing.expectEqual(@as(?i32, 1), ch.next());
    try std.testing.expectEqual(@as(?i32, 2), ch.next());
    try std.testing.expectEqual(@as(?i32, 3), ch.next());
    try std.testing.expectEqual(@as(?i32, 4), ch.next());
    try std.testing.expectEqual(@as(?i32, 5), ch.next());
    try std.testing.expectEqual(@as(?i32, null), ch.next());
}

test "islice iterator" {
    const data = [_]i32{ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9 };
    var sl = islice(i32, &data, 5);
    try std.testing.expectEqual(@as(?i32, 0), sl.next());
    try std.testing.expectEqual(@as(?i32, 1), sl.next());
    try std.testing.expectEqual(@as(?i32, 2), sl.next());
    try std.testing.expectEqual(@as(?i32, 3), sl.next());
    try std.testing.expectEqual(@as(?i32, 4), sl.next());
    try std.testing.expectEqual(@as(?i32, null), sl.next());
}

test "pairwise iterator" {
    const data = [_]i32{ 1, 2, 3, 4 };
    var pw = pairwise(i32, &data);
    try std.testing.expectEqual(@as(?struct { i32, i32 }, .{ 1, 2 }), pw.next());
    try std.testing.expectEqual(@as(?struct { i32, i32 }, .{ 2, 3 }), pw.next());
    try std.testing.expectEqual(@as(?struct { i32, i32 }, .{ 3, 4 }), pw.next());
    try std.testing.expectEqual(@as(?struct { i32, i32 }, null), pw.next());
}

test "combinations iterator" {
    const data = [_]i32{ 1, 2, 3, 4 };
    var comb = CombinationsIterator(i32, 2).init(&data);

    try std.testing.expectEqual(@as(?[2]i32, .{ 1, 2 }), comb.next());
    try std.testing.expectEqual(@as(?[2]i32, .{ 1, 3 }), comb.next());
    try std.testing.expectEqual(@as(?[2]i32, .{ 1, 4 }), comb.next());
    try std.testing.expectEqual(@as(?[2]i32, .{ 2, 3 }), comb.next());
    try std.testing.expectEqual(@as(?[2]i32, .{ 2, 4 }), comb.next());
    try std.testing.expectEqual(@as(?[2]i32, .{ 3, 4 }), comb.next());
    try std.testing.expectEqual(@as(?[2]i32, null), comb.next());
}
