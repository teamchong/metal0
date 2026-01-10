//! test.test_zoneinfo.test_part4 - Fold handling for ambiguous times
//!
//! This module handles the "fold" attribute for ambiguous datetimes:
//! - When DST ends, clocks fall back creating ambiguous times
//! - fold=0: First occurrence (DST time)
//! - fold=1: Second occurrence (standard time)
//! - Gap detection when DST starts

const std = @import("std");
const testing = std.testing;
const mem = std.mem;
const Allocator = mem.Allocator;

/// Time classification for DST transitions
pub const TimeClassification = enum {
    /// Normal time (unambiguous, not in a gap)
    normal,
    /// Ambiguous time (during fall-back, time occurs twice)
    ambiguous,
    /// Gap time (during spring-forward, time doesn't exist)
    gap,
    /// Before any transitions
    before_transitions,
    /// After all transitions
    after_transitions,

    pub fn isValid(self: TimeClassification) bool {
        return self == .normal or self == .ambiguous;
    }

    pub fn needsFold(self: TimeClassification) bool {
        return self == .ambiguous;
    }
};

/// Represents an ambiguous time period
pub const AmbiguousPeriod = struct {
    /// Start of the ambiguous period (in local time)
    start_local: i64,
    /// End of the ambiguous period (in local time)
    end_local: i64,
    /// Offset before the transition (DST)
    offset_before: i32,
    /// Offset after the transition (standard)
    offset_after: i32,

    /// Duration of the ambiguous period in seconds
    pub fn duration(self: AmbiguousPeriod) i64 {
        return self.end_local - self.start_local;
    }

    /// Check if a local time falls within this ambiguous period
    pub fn contains(self: AmbiguousPeriod, local_time: i64) bool {
        return local_time >= self.start_local and local_time < self.end_local;
    }

    /// Get the UTC time for fold=0 (first occurrence)
    pub fn toUtcFold0(self: AmbiguousPeriod, local_time: i64) i64 {
        return local_time - self.offset_before;
    }

    /// Get the UTC time for fold=1 (second occurrence)
    pub fn toUtcFold1(self: AmbiguousPeriod, local_time: i64) i64 {
        return local_time - self.offset_after;
    }

    /// Get UTC time based on fold value
    pub fn toUtc(self: AmbiguousPeriod, local_time: i64, fold: u1) i64 {
        return if (fold == 0) self.toUtcFold0(local_time) else self.toUtcFold1(local_time);
    }
};

/// Represents a gap period (time that doesn't exist)
pub const GapPeriod = struct {
    /// Start of the gap (in local time)
    start_local: i64,
    /// End of the gap (in local time)
    end_local: i64,
    /// Offset before the transition (standard)
    offset_before: i32,
    /// Offset after the transition (DST)
    offset_after: i32,

    /// Duration of the gap in seconds
    pub fn duration(self: GapPeriod) i64 {
        return self.end_local - self.start_local;
    }

    /// Check if a local time falls within this gap
    pub fn contains(self: GapPeriod, local_time: i64) bool {
        return local_time >= self.start_local and local_time < self.end_local;
    }

    /// Normalize a gap time to after the gap
    pub fn normalizeForward(self: GapPeriod, local_time: i64) i64 {
        if (!self.contains(local_time)) return local_time;
        return self.end_local + (local_time - self.start_local);
    }

    /// Normalize a gap time to before the gap
    pub fn normalizeBackward(self: GapPeriod, local_time: i64) i64 {
        if (!self.contains(local_time)) return local_time;
        return self.start_local - 1;
    }
};

/// DST transition information
pub const DSTTransition = struct {
    /// UTC timestamp of the transition
    utc_time: i64,
    /// Offset before transition
    offset_before: i32,
    /// Offset after transition
    offset_after: i32,
    /// Whether this creates a gap (spring forward) or fold (fall back)
    is_gap: bool,

    /// Create a spring-forward (gap) transition
    pub fn springForward(utc_time: i64, std_offset: i32, dst_offset: i32) DSTTransition {
        return .{
            .utc_time = utc_time,
            .offset_before = std_offset,
            .offset_after = dst_offset,
            .is_gap = true,
        };
    }

    /// Create a fall-back (fold) transition
    pub fn fallBack(utc_time: i64, dst_offset: i32, std_offset: i32) DSTTransition {
        return .{
            .utc_time = utc_time,
            .offset_before = dst_offset,
            .offset_after = std_offset,
            .is_gap = false,
        };
    }

    /// Get the change in offset
    pub fn offsetChange(self: DSTTransition) i32 {
        return self.offset_after - self.offset_before;
    }

    /// Get the local time just before transition
    pub fn localTimeBefore(self: DSTTransition) i64 {
        return self.utc_time + self.offset_before;
    }

    /// Get the local time just after transition
    pub fn localTimeAfter(self: DSTTransition) i64 {
        return self.utc_time + self.offset_after;
    }

    /// Convert to ambiguous period (for fall-back)
    pub fn toAmbiguousPeriod(self: DSTTransition) ?AmbiguousPeriod {
        if (self.is_gap) return null;
        return .{
            .start_local = self.localTimeAfter(),
            .end_local = self.localTimeBefore(),
            .offset_before = self.offset_before,
            .offset_after = self.offset_after,
        };
    }

    /// Convert to gap period (for spring-forward)
    pub fn toGapPeriod(self: DSTTransition) ?GapPeriod {
        if (!self.is_gap) return null;
        return .{
            .start_local = self.localTimeBefore(),
            .end_local = self.localTimeAfter(),
            .offset_before = self.offset_before,
            .offset_after = self.offset_after,
        };
    }
};

/// Fold-aware local time representation
pub const FoldAwareTime = struct {
    /// Local timestamp
    local_time: i64,
    /// Fold value (0 or 1)
    fold: u1,
    /// Time classification
    classification: TimeClassification,

    /// Create a normal (unambiguous) time
    pub fn normal(local_time: i64) FoldAwareTime {
        return .{
            .local_time = local_time,
            .fold = 0,
            .classification = .normal,
        };
    }

    /// Create an ambiguous time with specified fold
    pub fn ambiguous(local_time: i64, fold: u1) FoldAwareTime {
        return .{
            .local_time = local_time,
            .fold = fold,
            .classification = .ambiguous,
        };
    }

    /// Create a gap time
    pub fn gap(local_time: i64) FoldAwareTime {
        return .{
            .local_time = local_time,
            .fold = 0,
            .classification = .gap,
        };
    }

    /// Check if this time is ambiguous
    pub fn isAmbiguous(self: FoldAwareTime) bool {
        return self.classification == .ambiguous;
    }

    /// Check if this time is in a gap
    pub fn isInGap(self: FoldAwareTime) bool {
        return self.classification == .gap;
    }

    /// Check if this time is valid (not in a gap)
    pub fn isValid(self: FoldAwareTime) bool {
        return self.classification.isValid();
    }

    /// Get the "other" fold value for ambiguous times
    pub fn otherFold(self: FoldAwareTime) ?FoldAwareTime {
        if (!self.isAmbiguous()) return null;
        return .{
            .local_time = self.local_time,
            .fold = if (self.fold == 0) 1 else 0,
            .classification = .ambiguous,
        };
    }
};

/// Fold resolver for determining UTC time from local time
pub const FoldResolver = struct {
    transitions: []const DSTTransition,

    pub fn init(transitions: []const DSTTransition) FoldResolver {
        return .{ .transitions = transitions };
    }

    /// Classify a local time
    pub fn classify(self: FoldResolver, local_time: i64) TimeClassification {
        for (self.transitions) |trans| {
            if (trans.is_gap) {
                if (trans.toGapPeriod()) |gap_period| {
                    if (gap_period.contains(local_time)) {
                        return .gap;
                    }
                }
            } else {
                if (trans.toAmbiguousPeriod()) |amb| {
                    if (amb.contains(local_time)) {
                        return .ambiguous;
                    }
                }
            }
        }
        return .normal;
    }

    /// Convert local time to UTC with fold
    pub fn toUtc(self: FoldResolver, local_time: i64, fold: u1) ?i64 {
        for (self.transitions) |trans| {
            if (!trans.is_gap) {
                if (trans.toAmbiguousPeriod()) |amb| {
                    if (amb.contains(local_time)) {
                        return amb.toUtc(local_time, fold);
                    }
                }
            }
        }
        // Not in an ambiguous period, fold is ignored
        return null;
    }

    /// Get the fold value for a UTC time that falls in an ambiguous period
    pub fn getFoldFromUtc(self: FoldResolver, utc_time: i64, offset: i32) ?u1 {
        for (self.transitions) |trans| {
            if (!trans.is_gap) {
                // fold=0 uses offset_before, fold=1 uses offset_after
                if (offset == trans.offset_before) return 0;
                if (offset == trans.offset_after) return 1;
            }
        }
        return null;
    }
};

/// US Eastern timezone DST transitions for testing
pub const USEasternTransitions = struct {
    pub const EST_OFFSET: i32 = -18000; // -5 hours
    pub const EDT_OFFSET: i32 = -14400; // -4 hours

    /// Spring forward 2023: March 12, 2:00 AM EST -> 3:00 AM EDT
    pub const SPRING_2023 = DSTTransition{
        .utc_time = 1678608000, // 2023-03-12 07:00:00 UTC
        .offset_before = EST_OFFSET,
        .offset_after = EDT_OFFSET,
        .is_gap = true,
    };

    /// Fall back 2023: November 5, 2:00 AM EDT -> 1:00 AM EST
    pub const FALL_2023 = DSTTransition{
        .utc_time = 1699164000, // 2023-11-05 06:00:00 UTC
        .offset_before = EDT_OFFSET,
        .offset_after = EST_OFFSET,
        .is_gap = false,
    };
};

// ============================================================================
// Tests
// ============================================================================

test "time_classification_is_valid" {
    try testing.expect(TimeClassification.normal.isValid());
    try testing.expect(TimeClassification.ambiguous.isValid());
    try testing.expect(!TimeClassification.gap.isValid());
}

test "time_classification_needs_fold" {
    try testing.expect(!TimeClassification.normal.needsFold());
    try testing.expect(TimeClassification.ambiguous.needsFold());
    try testing.expect(!TimeClassification.gap.needsFold());
}

test "ambiguous_period_duration" {
    const period = AmbiguousPeriod{
        .start_local = 1000,
        .end_local = 4600,
        .offset_before = -14400,
        .offset_after = -18000,
    };
    try testing.expectEqual(@as(i64, 3600), period.duration());
}

test "ambiguous_period_contains" {
    const period = AmbiguousPeriod{
        .start_local = 1000,
        .end_local = 4600,
        .offset_before = -14400,
        .offset_after = -18000,
    };
    try testing.expect(period.contains(1000));
    try testing.expect(period.contains(2000));
    try testing.expect(!period.contains(4600));
    try testing.expect(!period.contains(999));
}

test "ambiguous_period_to_utc" {
    const period = AmbiguousPeriod{
        .start_local = 100000,
        .end_local = 103600,
        .offset_before = -14400,
        .offset_after = -18000,
    };
    const local_time: i64 = 101800;

    const utc_fold0 = period.toUtcFold0(local_time);
    const utc_fold1 = period.toUtcFold1(local_time);

    try testing.expectEqual(@as(i64, 116200), utc_fold0);
    try testing.expectEqual(@as(i64, 119800), utc_fold1);
}

test "gap_period_duration" {
    const period = GapPeriod{
        .start_local = 1000,
        .end_local = 4600,
        .offset_before = -18000,
        .offset_after = -14400,
    };
    try testing.expectEqual(@as(i64, 3600), period.duration());
}

test "gap_period_contains" {
    const period = GapPeriod{
        .start_local = 1000,
        .end_local = 4600,
        .offset_before = -18000,
        .offset_after = -14400,
    };
    try testing.expect(period.contains(1000));
    try testing.expect(period.contains(2000));
    try testing.expect(!period.contains(4600));
}

test "gap_period_normalize_forward" {
    const period = GapPeriod{
        .start_local = 1000,
        .end_local = 4600,
        .offset_before = -18000,
        .offset_after = -14400,
    };

    try testing.expectEqual(@as(i64, 5600), period.normalizeForward(2000));
    try testing.expectEqual(@as(i64, 5000), period.normalizeForward(500));
}

test "gap_period_normalize_backward" {
    const period = GapPeriod{
        .start_local = 1000,
        .end_local = 4600,
        .offset_before = -18000,
        .offset_after = -14400,
    };

    try testing.expectEqual(@as(i64, 999), period.normalizeBackward(2000));
}

test "dst_transition_spring_forward" {
    const trans = DSTTransition.springForward(1678608000, -18000, -14400);
    try testing.expect(trans.is_gap);
    try testing.expectEqual(@as(i32, 3600), trans.offsetChange());
}

test "dst_transition_fall_back" {
    const trans = DSTTransition.fallBack(1699164000, -14400, -18000);
    try testing.expect(!trans.is_gap);
    try testing.expectEqual(@as(i32, -3600), trans.offsetChange());
}

test "dst_transition_local_times" {
    const trans = DSTTransition.springForward(1678608000, -18000, -14400);
    const local_before = trans.localTimeBefore();
    const local_after = trans.localTimeAfter();
    try testing.expect(local_after > local_before);
}

test "dst_transition_to_gap_period" {
    const trans = DSTTransition.springForward(1678608000, -18000, -14400);
    const gap = trans.toGapPeriod();
    try testing.expect(gap != null);
    try testing.expectEqual(@as(i64, 3600), gap.?.duration());
}

test "dst_transition_to_ambiguous_period" {
    const trans = DSTTransition.fallBack(1699164000, -14400, -18000);
    const amb = trans.toAmbiguousPeriod();
    try testing.expect(amb != null);
    try testing.expectEqual(@as(i64, 3600), amb.?.duration());
}

test "fold_aware_time_normal" {
    const t = FoldAwareTime.normal(1000000);
    try testing.expect(!t.isAmbiguous());
    try testing.expect(!t.isInGap());
    try testing.expect(t.isValid());
}

test "fold_aware_time_ambiguous" {
    const t = FoldAwareTime.ambiguous(1000000, 0);
    try testing.expect(t.isAmbiguous());
    try testing.expect(!t.isInGap());
    try testing.expect(t.isValid());
}

test "fold_aware_time_gap" {
    const t = FoldAwareTime.gap(1000000);
    try testing.expect(!t.isAmbiguous());
    try testing.expect(t.isInGap());
    try testing.expect(!t.isValid());
}

test "fold_aware_time_other_fold" {
    const t0 = FoldAwareTime.ambiguous(1000000, 0);
    const t1 = t0.otherFold();
    try testing.expect(t1 != null);
    try testing.expectEqual(@as(u1, 1), t1.?.fold);

    const normal = FoldAwareTime.normal(1000000);
    try testing.expect(normal.otherFold() == null);
}

test "us_eastern_spring_2023_is_gap" {
    try testing.expect(USEasternTransitions.SPRING_2023.is_gap);
    try testing.expectEqual(@as(i32, 3600), USEasternTransitions.SPRING_2023.offsetChange());
}

test "us_eastern_fall_2023_is_fold" {
    try testing.expect(!USEasternTransitions.FALL_2023.is_gap);
    try testing.expectEqual(@as(i32, -3600), USEasternTransitions.FALL_2023.offsetChange());
}

test "fold_resolver_classify_normal" {
    const trans = [_]DSTTransition{USEasternTransitions.FALL_2023};
    const resolver = FoldResolver.init(&trans);

    const classification = resolver.classify(1000000000);
    try testing.expectEqual(TimeClassification.normal, classification);
}

test "fold_resolver_classify_ambiguous" {
    const trans = [_]DSTTransition{USEasternTransitions.FALL_2023};
    const resolver = FoldResolver.init(&trans);

    const amb = USEasternTransitions.FALL_2023.toAmbiguousPeriod().?;
    const ambiguous_time = amb.start_local + 1800;

    const classification = resolver.classify(ambiguous_time);
    try testing.expectEqual(TimeClassification.ambiguous, classification);
}

test "fold_resolver_classify_gap" {
    const trans = [_]DSTTransition{USEasternTransitions.SPRING_2023};
    const resolver = FoldResolver.init(&trans);

    const gap = USEasternTransitions.SPRING_2023.toGapPeriod().?;
    const gap_time = gap.start_local + 1800;

    const classification = resolver.classify(gap_time);
    try testing.expectEqual(TimeClassification.gap, classification);
}
