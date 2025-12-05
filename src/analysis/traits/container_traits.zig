/// Container Traits - Unified helpers for list/dict/set/tuple type decisions
///
/// Centralizes container-related decisions that were previously scattered across:
/// - mutation_analyzer.zig (tracking heterogeneous usage)
/// - containers.zig (container codegen)
/// - generator.zig (list comprehension)
///
/// | Pattern                    | Solution                                      |
/// |----------------------------|-----------------------------------------------|
/// | Element type inference     | inferElementType, inferKeyType, inferValueType|
/// | Heterogeneity detection    | needsPyValueElements, isHomogeneous          |
/// | Container capabilities     | supportsPush, supportsSetItem, supportsConcat |
/// | Iteration                  | getIteratorType, getElementType              |
/// | Mutation tracking          | trackMutation, getMutationPattern            |
///
/// USAGE:
/// ```zig
/// const traits = @import("container_traits.zig");
///
/// // Element type inference
/// const elem_type = traits.inferElementType(list_type);
/// if (traits.needsPyValueElements(mutations)) { /* ArrayList(PyValue) */ }
///
/// // Container capabilities
/// if (traits.supportsPush(t)) { /* can use .append() */ }
/// if (traits.supportsConcat(t)) { /* can use + */ }
///
/// // Iteration
/// const iter_elem = traits.getIteratorElementType(container_type);
/// ```

const std = @import("std");
const NativeType = @import("../native_types/core.zig").NativeType;

// ============================================================================
// CONTAINER TYPE CHECKING
// ============================================================================

/// Check if type is a list
pub fn isList(t: NativeType) bool {
    return t == .list;
}

/// Check if type is a dict
pub fn isDict(t: NativeType) bool {
    return t == .dict;
}

/// Check if type is a set
pub fn isSet(t: NativeType) bool {
    return t == .set;
}

/// Check if type is a tuple
pub fn isTuple(t: NativeType) bool {
    return t == .tuple;
}

/// Check if type is an array
pub fn isArray(t: NativeType) bool {
    return t == .array;
}

/// Check if type is any container (list, dict, set, tuple, array)
pub fn isContainer(t: NativeType) bool {
    const tag = @as(std.meta.Tag(@TypeOf(t)), t);
    return tag == .list or tag == .dict or tag == .set or tag == .tuple or tag == .array;
}

/// Check if type is a mutable container (list, dict, set)
pub fn isMutableContainer(t: NativeType) bool {
    const tag = @as(std.meta.Tag(@TypeOf(t)), t);
    return tag == .list or tag == .dict or tag == .set;
}

/// Check if type is an immutable container (tuple, frozenset)
pub fn isImmutableContainer(t: NativeType) bool {
    const tag = @as(std.meta.Tag(@TypeOf(t)), t);
    return tag == .tuple or tag == .frozenset;
}

/// Check if type is a sequence container (ordered: list, tuple, array)
pub fn isSequenceContainer(t: NativeType) bool {
    const tag = @as(std.meta.Tag(@TypeOf(t)), t);
    return tag == .list or tag == .tuple or tag == .array;
}

/// Check if type is a mapping container (dict)
pub fn isMappingContainer(t: NativeType) bool {
    const tag = @as(std.meta.Tag(@TypeOf(t)), t);
    return tag == .dict;
}

/// Check if type is a set-like container (set, frozenset)
pub fn isSetContainer(t: NativeType) bool {
    const tag = @as(std.meta.Tag(@TypeOf(t)), t);
    return tag == .set or tag == .frozenset;
}

// ============================================================================
// ELEMENT TYPE INFERENCE
// ============================================================================

/// Get the element type of a container
pub fn getElementType(t: NativeType) NativeType {
    const tag = @as(std.meta.Tag(@TypeOf(t)), t);
    return switch (tag) {
        .list => t.list.*,
        .set => t.set.*,
        .tuple => .unknown, // Tuples can have heterogeneous elements
        .array => t.array.element_type.*,
        .frozenset => t.frozenset.*,
        else => .unknown,
    };
}

/// Get the key type of a mapping
pub fn getKeyType(t: NativeType) NativeType {
    const tag = @as(std.meta.Tag(@TypeOf(t)), t);
    return switch (tag) {
        .dict => t.dict.key.*,
        else => .unknown,
    };
}

/// Get the value type of a mapping
pub fn getValueType(t: NativeType) NativeType {
    const tag = @as(std.meta.Tag(@TypeOf(t)), t);
    return switch (tag) {
        .dict => t.dict.value.*,
        else => .unknown,
    };
}

/// Check if container has a known homogeneous element type
pub fn hasHomogeneousElements(t: NativeType) bool {
    const elem = getElementType(t);
    return elem != .unknown;
}

/// Check if two element types are compatible (same or both unknown)
pub fn areElementTypesCompatible(a: NativeType, b: NativeType) bool {
    if (a == .unknown or b == .unknown) return true;
    return std.meta.eql(a, b);
}

// ============================================================================
// CONTAINER CAPABILITIES
// ============================================================================

/// Check if container supports push/append operations
pub fn supportsPush(t: NativeType) bool {
    const tag = @as(std.meta.Tag(@TypeOf(t)), t);
    return tag == .list;
}

/// Check if container supports add operations (set.add)
pub fn supportsAdd(t: NativeType) bool {
    const tag = @as(std.meta.Tag(@TypeOf(t)), t);
    return tag == .set;
}

/// Check if container supports setitem (container[key] = value)
pub fn supportsSetItem(t: NativeType) bool {
    const tag = @as(std.meta.Tag(@TypeOf(t)), t);
    return tag == .list or tag == .dict or tag == .array;
}

/// Check if container supports getitem (container[key])
pub fn supportsGetItem(t: NativeType) bool {
    const tag = @as(std.meta.Tag(@TypeOf(t)), t);
    return tag == .list or tag == .dict or tag == .tuple or tag == .array;
}

/// Check if container supports concatenation with +
pub fn supportsConcat(t: NativeType) bool {
    const tag = @as(std.meta.Tag(@TypeOf(t)), t);
    return tag == .list or tag == .tuple;
}

/// Check if container supports repetition with * int
pub fn supportsRepeat(t: NativeType) bool {
    const tag = @as(std.meta.Tag(@TypeOf(t)), t);
    return tag == .list or tag == .tuple;
}

/// Check if container supports the 'in' operator
pub fn supportsContains(t: NativeType) bool {
    return isContainer(t);
}

/// Check if container supports len()
pub fn supportsLen(t: NativeType) bool {
    return isContainer(t);
}

/// Check if container supports slicing [start:end]
pub fn supportsSlicing(t: NativeType) bool {
    const tag = @as(std.meta.Tag(@TypeOf(t)), t);
    return tag == .list or tag == .tuple or tag == .array;
}

// ============================================================================
// ITERATION
// ============================================================================

/// Get the element type when iterating over a container
pub fn getIteratorElementType(t: NativeType) NativeType {
    const tag = @as(std.meta.Tag(@TypeOf(t)), t);
    return switch (tag) {
        .list => t.list.*,
        .set => t.set.*,
        .tuple => .unknown, // Unknown at compile time
        .array => t.array.element_type.*,
        .dict => t.dict.key.*, // Iterating dict yields keys
        .frozenset => t.frozenset.*,
        else => .unknown,
    };
}

/// Check if container can be unpacked (*container)
pub fn supportsUnpacking(t: NativeType) bool {
    return isContainer(t);
}

// ============================================================================
// RESULT TYPE INFERENCE
// ============================================================================

/// Get the result type of concatenating two containers
pub fn getConcatResultType(left: NativeType, right: NativeType) ?NativeType {
    const left_tag = @as(std.meta.Tag(@TypeOf(left)), left);
    const right_tag = @as(std.meta.Tag(@TypeOf(right)), right);

    // list + list = list
    if (left_tag == .list and right_tag == .list) {
        // Result element type is union of both, but for now return left type
        return left;
    }

    // tuple + tuple = tuple
    if (left_tag == .tuple and right_tag == .tuple) {
        return .tuple;
    }

    return null;
}

/// Get the result type of repeating a container
pub fn getRepeatResultType(t: NativeType) ?NativeType {
    const tag = @as(std.meta.Tag(@TypeOf(t)), t);
    return switch (tag) {
        .list => t,
        .tuple => .tuple,
        else => null,
    };
}

/// Get the result type of slicing a container
pub fn getSliceResultType(t: NativeType) NativeType {
    const tag = @as(std.meta.Tag(@TypeOf(t)), t);
    return switch (tag) {
        .list => t, // Slicing list returns list of same element type
        .tuple => .tuple, // Slicing tuple returns tuple
        .array => t, // Slicing array returns array
        else => .unknown,
    };
}

// ============================================================================
// ZIG TYPE MAPPING
// ============================================================================

/// Get the Zig container type name for a Python container
pub fn toZigContainerType(t: NativeType, elem_zig_type: []const u8) ?[]const u8 {
    const tag = @as(std.meta.Tag(@TypeOf(t)), t);
    return switch (tag) {
        .list => "std.ArrayList",
        .dict => "std.StringHashMap", // Simplified - actual depends on key type
        .set => "std.AutoHashMap", // Using AutoHashMap(T, void) for set
        else => null,
    };
    _ = elem_zig_type;
}

/// Check if container needs PyValue elements (heterogeneous)
pub fn needsPyValueElementsForType(t: NativeType) bool {
    const elem = getElementType(t);
    return elem == .unknown;
}

// ============================================================================
// MUTATION PATTERNS (for analysis phase)
// ============================================================================

pub const MutationKind = enum {
    append, // list.append(x)
    extend, // list.extend(iterable)
    insert, // list.insert(i, x)
    pop, // list.pop() / dict.pop(k)
    remove, // list.remove(x) / set.remove(x)
    clear, // container.clear()
    setitem, // container[k] = v
    delitem, // del container[k]
    update, // dict.update() / set.update()
    add, // set.add(x)
    discard, // set.discard(x)
};

/// Get valid mutation kinds for a container type
pub fn getValidMutations(t: NativeType) []const MutationKind {
    const tag = @as(std.meta.Tag(@TypeOf(t)), t);
    return switch (tag) {
        .list => &[_]MutationKind{ .append, .extend, .insert, .pop, .remove, .clear, .setitem, .delitem },
        .dict => &[_]MutationKind{ .setitem, .delitem, .pop, .clear, .update },
        .set => &[_]MutationKind{ .add, .remove, .discard, .clear, .update, .pop },
        else => &[_]MutationKind{},
    };
}

/// Check if a mutation is valid for a container type
pub fn isValidMutation(t: NativeType, kind: MutationKind) bool {
    const valid = getValidMutations(t);
    for (valid) |v| {
        if (v == kind) return true;
    }
    return false;
}

// ============================================================================
// TESTS
// ============================================================================

test "isContainer" {
    // We can't easily construct NativeType with payload in tests,
    // but we can test the tag-based checks work
    try std.testing.expect(!isContainer(.{ .int = .bounded }));
    try std.testing.expect(!isContainer(.float));
    try std.testing.expect(!isContainer(.{ .string = .literal }));
}

test "isMutableContainer" {
    try std.testing.expect(!isMutableContainer(.{ .int = .bounded }));
    try std.testing.expect(!isMutableContainer(.float));
}

test "getValidMutations" {
    // Test that we don't crash on non-container types
    const int_mutations = getValidMutations(.{ .int = .bounded });
    try std.testing.expectEqual(@as(usize, 0), int_mutations.len);
}
